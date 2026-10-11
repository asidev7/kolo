"""Les catégories par défaut sont un contrat entre le téléphone et le serveur."""

import re
from pathlib import Path

import pytest

from apps.categories.models import Category

DART_FILE = (
    Path(__file__).resolve().parents[2] / "mobile/lib/core/constants/default_categories.dart"
)
_ENTRY = re.compile(
    r"DefaultCategory\(\s*id: '([^']+)',\s*name: '([^']+)',\s*"
    r"type: TransactionType\.(\w+),\s*icon: '([^']+)',\s*sortOrder: (\d+),",
)


def mobile_defaults():
    if not DART_FILE.exists():
        pytest.skip("Application mobile absente de ce dépôt.")
    return {
        (cat_id, name, cat_type, icon, int(order))
        for cat_id, name, cat_type, icon, order in _ENTRY.findall(
            DART_FILE.read_text(encoding="utf-8")
        )
    }


@pytest.mark.django_db
def test_same_categories_as_mobile_app():
    expected = mobile_defaults()
    assert len(expected) == 15
    actual = {
        (str(c.pk), c.name, c.type, c.icon, c.sort_order)
        for c in Category.objects.filter(is_default=True)
    }
    assert actual == expected


@pytest.mark.django_db
def test_defaults_belong_to_nobody():
    assert not Category.objects.filter(is_default=True, user__isnull=False).exists()
