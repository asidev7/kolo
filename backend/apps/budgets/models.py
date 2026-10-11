from django.db import models

from apps.categories.models import Category
from apps.core.constants import DEFAULT_CURRENCY
from apps.core.models import SyncModel


def default_thresholds() -> list[int]:
    return [80, 100]


class Budget(SyncModel):
    """Plafond mensuel. `category` nul = budget global (seul cas en v1)."""

    SYNC_FIELDS = ("period", "category_id", "limit_amount", "currency", "alert_thresholds")

    period = models.CharField(max_length=7)  # YYYY-MM
    category = models.ForeignKey(
        Category, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    limit_amount = models.BigIntegerField()
    currency = models.CharField(max_length=3, default=DEFAULT_CURRENCY)
    alert_thresholds = models.JSONField(default=default_thresholds)

    class Meta:
        db_table = "budgets"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(limit_amount__gte=0), name="budgets_limit_non_negative"
            ),
            # Deux contraintes partielles plutôt qu'une : PostgreSQL considère
            # deux NULL comme distincts dans un index unique.
            models.UniqueConstraint(
                "user",
                "period",
                condition=models.Q(deleted_at__isnull=True, category__isnull=True),
                name="budgets_owner_period_global",
            ),
            models.UniqueConstraint(
                "user",
                "period",
                "category",
                condition=models.Q(deleted_at__isnull=True, category__isnull=False),
                name="budgets_owner_period_category",
            ),
        ]
        indexes = [models.Index(fields=["user", "change_seq"], name="budgets_user_seq")]

    def sync_data(self) -> dict:
        return {
            "period": self.period,
            "category_id": str(self.category_id) if self.category_id else None,
            "limit_amount": self.limit_amount,
            "currency": self.currency,
            "alert_thresholds": list(self.alert_thresholds),
        }
