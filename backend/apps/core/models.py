from django.conf import settings
from django.db import models


class SyncModel(models.Model):
    """Champs communs aux entités synchronisées (ARCHITECTURE.md §5.1).

    - `id` est généré par le client (UUID v4), jamais par le serveur.
    - `version` et `server_updated_at` sont attribués **uniquement** par le
      serveur ; aucune horloge de téléphone n'intervient dans les conflits.
    - `change_seq` ordonne les changements d'un compte : c'est le curseur de
      `sync/pull`.
    - `field_versions` mémorise, pour chaque champ, la version à laquelle il a
      changé pour la dernière fois : il rend la fusion champ par champ exacte.
    """

    #: Champs métier échangés dans `data` (dans l'ordre de l'API).
    SYNC_FIELDS: tuple[str, ...] = ()

    id = models.UUIDField(primary_key=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.CASCADE, related_name="+"
    )
    created_at = models.DateTimeField()
    updated_at = models.DateTimeField()
    version = models.PositiveIntegerField(default=0)
    server_updated_at = models.DateTimeField()
    deleted_at = models.DateTimeField(null=True, blank=True)
    change_seq = models.BigIntegerField(default=0)
    field_versions = models.JSONField(default=dict, blank=True)

    class Meta:
        abstract = True

    def sync_data(self) -> dict:
        """Instantané au format de l'API (clés de `Payloads` côté mobile)."""
        raise NotImplementedError
