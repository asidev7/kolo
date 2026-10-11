"""Catégories par défaut — copie exacte de
`mobile/lib/core/constants/default_categories.dart`.

Ces UUID sont un contrat avec l'application : ne jamais les modifier ni les
réutiliser. `tests/test_default_categories.py` vérifie que les deux listes
restent identiques.
"""

from datetime import UTC, datetime

from django.db import migrations

CREATED_AT = datetime(2026, 1, 1, tzinfo=UTC)

DEFAULT_CATEGORIES = [
    # (id, nom, type, icône, ordre)
    ("c0a7e9e0-0000-4000-8000-000000000001", "Alimentation", "expense", "food", 10),
    ("c0a7e9e0-0000-4000-8000-000000000002", "Transport", "expense", "transport", 20),
    ("c0a7e9e0-0000-4000-8000-000000000003", "Logement", "expense", "home", 30),
    ("c0a7e9e0-0000-4000-8000-000000000004", "Études", "expense", "school", 40),
    ("c0a7e9e0-0000-4000-8000-000000000005", "Santé", "expense", "health", 50),
    ("c0a7e9e0-0000-4000-8000-000000000006", "Communication", "expense", "phone", 60),
    ("c0a7e9e0-0000-4000-8000-000000000007", "Loisirs", "expense", "leisure", 70),
    ("c0a7e9e0-0000-4000-8000-000000000008", "Factures", "expense", "bills", 80),
    ("c0a7e9e0-0000-4000-8000-000000000009", "Autres", "expense", "other", 990),
    ("c0a7e9e0-0000-4000-8000-000000000101", "Salaire", "income", "salary", 10),
    ("c0a7e9e0-0000-4000-8000-000000000102", "Activité indépendante", "income", "freelance", 20),
    ("c0a7e9e0-0000-4000-8000-000000000103", "Bourse", "income", "scholarship", 30),
    ("c0a7e9e0-0000-4000-8000-000000000104", "Aide familiale", "income", "family", 40),
    ("c0a7e9e0-0000-4000-8000-000000000105", "Vente", "income", "sale", 50),
    ("c0a7e9e0-0000-4000-8000-000000000106", "Autres", "income", "other", 990),
]


def create_defaults(apps, schema_editor):
    Category = apps.get_model("categories", "Category")
    for cat_id, name, cat_type, icon, sort_order in DEFAULT_CATEGORIES:
        Category.objects.update_or_create(
            id=cat_id,
            defaults={
                "user": None,
                "name": name,
                "type": cat_type,
                "icon": icon,
                "color": None,
                "is_default": True,
                "sort_order": sort_order,
                "created_at": CREATED_AT,
                "updated_at": CREATED_AT,
                "server_updated_at": CREATED_AT,
                "version": 1,
                "change_seq": 0,
                "field_versions": {},
            },
        )


def remove_defaults(apps, schema_editor):
    Category = apps.get_model("categories", "Category")
    Category.objects.filter(id__in=[c[0] for c in DEFAULT_CATEGORIES], user=None).delete()


class Migration(migrations.Migration):
    dependencies = [("categories", "0001_initial")]

    operations = [migrations.RunPython(create_defaults, remove_defaults)]
