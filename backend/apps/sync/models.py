from django.conf import settings
from django.db import models
from django.utils import timezone


class SyncCounter(models.Model):
    """Compteur `change_seq` d'un compte.

    Chaque push verrouille cette ligne (`SELECT … FOR UPDATE`) : les écritures
    d'un même compte sont sérialisées, donc un `change_seq` n'est jamais visible
    avant un `change_seq` plus petit. Le curseur de pull ne saute aucun
    changement.
    """

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, primary_key=True, on_delete=models.CASCADE, related_name="+"
    )
    last_seq = models.BigIntegerField(default=0)
    #: Plus grand `change_seq` d'un tombstone effacé définitivement. Un curseur
    #: plus ancien a pu manquer une suppression : resynchronisation complète.
    purged_seq = models.BigIntegerField(default=0)

    class Meta:
        db_table = "sync_counters"


class ProcessedOperation(models.Model):
    """Opération appliquée (idempotence, SYNC.md §1.5).

    Seules les opérations **appliquées** sont mémorisées : un conflit ou un
    rejet ne modifie rien, le réévaluer est sans danger. Le résultat stocké est
    renvoyé tel quel (statut `duplicate`) si le même `op_id` revient.
    """

    op_id = models.UUIDField(primary_key=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    device_id = models.CharField(max_length=64, blank=True)
    entity = models.CharField(max_length=16)
    entity_id = models.UUIDField()
    result = models.JSONField()
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "sync_processed_operations"
        indexes = [models.Index(fields=["created_at"], name="sync_processed_created")]
