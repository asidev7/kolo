from django.db import models

from apps.categories.models import Category, TransactionType
from apps.core.constants import DEFAULT_CURRENCY, MAX_AMOUNT, MAX_NOTE_LENGTH
from apps.core.models import SyncModel


class Transaction(SyncModel):
    """Revenu ou dépense. Montant entier dans la plus petite unité (1 = 1 F CFA)."""

    SYNC_FIELDS = ("type", "amount", "currency", "category_id", "note", "occurred_on")

    type = models.CharField(max_length=7, choices=TransactionType.choices)
    amount = models.BigIntegerField()
    currency = models.CharField(max_length=3, default=DEFAULT_CURRENCY)
    category = models.ForeignKey(Category, on_delete=models.PROTECT, related_name="+")
    note = models.CharField(max_length=MAX_NOTE_LENGTH, null=True, blank=True)
    occurred_on = models.DateField()

    class Meta:
        db_table = "transactions"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(amount__gt=0, amount__lte=MAX_AMOUNT),
                name="transactions_amount_range",
            ),
        ]
        indexes = [
            models.Index(fields=["user", "change_seq"], name="transactions_user_seq"),
            models.Index(fields=["user", "occurred_on"], name="transactions_user_date"),
        ]

    def sync_data(self) -> dict:
        return {
            "type": self.type,
            "amount": self.amount,
            "currency": self.currency,
            "category_id": str(self.category_id),
            "note": self.note,
            "occurred_on": self.occurred_on.isoformat(),
        }
