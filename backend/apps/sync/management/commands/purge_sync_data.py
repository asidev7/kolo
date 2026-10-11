"""Efface définitivement les données supprimées depuis plus de 90 jours.

À lancer une fois par jour (cron du serveur, voir deploy/native/). PRIVACY.md : « une
opération supprimée est définitivement effacée du serveur 90 jours après sa
suppression ».

Pour chaque compte, `SyncCounter.purged_seq` retient le plus grand
`change_seq` effacé : un téléphone dont le curseur est plus ancien a pu manquer
une suppression et doit repartir de zéro (`410 cursor_reset_required`).
"""

from datetime import timedelta

from django.conf import settings
from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Max
from django.utils import timezone

from apps.budgets.models import Budget
from apps.categories.models import Category
from apps.sync.models import ProcessedOperation, SyncCounter
from apps.transactions.models import Transaction


class Command(BaseCommand):
    help = "Efface les tombstones et opérations traitées de plus de 90 jours."

    def add_arguments(self, parser):
        parser.add_argument("--days", type=int, default=settings.KOLO_TOMBSTONE_RETENTION_DAYS)

    def handle(self, *args, days: int, **options):
        limit = timezone.now() - timedelta(days=days)
        totals = {"transaction": 0, "budget": 0, "category": 0}

        for name, model in (("transaction", Transaction), ("budget", Budget)):
            totals[name] = self._purge(model, model.objects.filter(deleted_at__lt=limit))

        # Une catégorie archivée reste tant qu'une opération (même supprimée
        # récemment) ou un budget y fait référence.
        referenced = set(Transaction.objects.values_list("category_id", flat=True).distinct())
        referenced |= set(
            Budget.objects.exclude(category=None).values_list("category_id", flat=True).distinct()
        )
        categories = Category.objects.filter(deleted_at__lt=limit, user__isnull=False).exclude(
            pk__in=referenced
        )
        totals["category"] = self._purge(Category, categories)

        ops, _ = ProcessedOperation.objects.filter(created_at__lt=limit).delete()
        self.stdout.write(
            "purge: "
            + ", ".join(f"{k}={v}" for k, v in totals.items())
            + f", processed_operations={ops}"
        )

    @staticmethod
    def _purge(model, queryset) -> int:
        per_user = queryset.values("user_id").annotate(seq=Max("change_seq"))
        count = 0
        for row in per_user:
            with transaction.atomic():
                counter, _ = SyncCounter.objects.select_for_update().get_or_create(
                    user_id=row["user_id"]
                )
                deleted, _ = queryset.filter(
                    user_id=row["user_id"], change_seq__lte=row["seq"]
                ).delete()
                if row["seq"] > counter.purged_seq:
                    counter.purged_seq = row["seq"]
                    counter.save(update_fields=["purged_seq"])
                count += deleted
        return count
