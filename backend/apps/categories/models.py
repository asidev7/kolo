from django.db import models
from django.db.models.functions import Lower

from apps.core.constants import MAX_CATEGORY_NAME_LENGTH
from apps.core.models import SyncModel


class TransactionType(models.TextChoices):
    EXPENSE = "expense"
    INCOME = "income"


class Category(SyncModel):
    """Catégorie par défaut (`user` nul, UUID fixe) ou personnalisée.

    Une catégorie archivée a un `deleted_at` : elle reste visible dans
    l'historique des opérations qui l'utilisent.
    """

    SYNC_FIELDS = ("name", "type", "icon", "color", "sort_order")

    name = models.CharField(max_length=MAX_CATEGORY_NAME_LENGTH)
    type = models.CharField(max_length=7, choices=TransactionType.choices)
    icon = models.CharField(max_length=40)
    color = models.CharField(max_length=7, null=True, blank=True)
    is_default = models.BooleanField(default=False)
    sort_order = models.IntegerField(default=0)

    class Meta:
        db_table = "categories"
        constraints = [
            models.UniqueConstraint(
                "user",
                "type",
                Lower("name"),
                condition=models.Q(deleted_at__isnull=True),
                name="categories_owner_type_name",
            ),
        ]
        indexes = [models.Index(fields=["user", "change_seq"], name="categories_user_seq")]

    def sync_data(self) -> dict:
        return {
            "name": self.name,
            "type": self.type,
            "icon": self.icon,
            "color": self.color,
            "sort_order": self.sort_order,
        }
