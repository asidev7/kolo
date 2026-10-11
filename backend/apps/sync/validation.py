"""Validation serveur des instantanés reçus par `sync/push`.

Mêmes règles que l'application (`TransactionValidator`, contraintes Drift) :
le serveur ne fait jamais confiance au client. Chaque fonction reçoit l'état
**cible complet** de l'enregistrement (après fusion) et renvoie les valeurs à
écrire dans le modèle, ou lève `Rejected`.
"""

import re
import uuid
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from apps.categories.models import Category
from apps.core.constants import (
    CURRENCIES,
    MAX_AMOUNT,
    MAX_CATEGORY_NAME_LENGTH,
    MAX_NOTE_LENGTH,
    TRANSACTION_TYPES,
)

_PERIOD_RE = re.compile(r"^(\d{4})-(0[1-9]|1[0-2])$")
_COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
_ICON_RE = re.compile(r"^[a-z0-9_]{1,40}$")
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

#: Fuseau le plus en avance (UTC+14). « Demain » y est la date la plus
#: lointaine qu'un téléphone puisse légitimement considérer comme J+1 : le
#: serveur ne rejette jamais une saisie acceptée hors ligne (ARCHITECTURE.md, D21).
_EARLIEST_ZONE = ZoneInfo("Pacific/Kiritimati")
MAX_DAYS_AHEAD = 1
MIN_DATE = date(2000, 1, 1)


class Rejected(Exception):  # noqa: N818 — vocabulaire du protocole (statut `rejected`)
    def __init__(self, code: str, message: str, fields: dict | None = None):
        super().__init__(code)
        self.code = code
        self.message = message
        self.fields = fields or {}


def _invalid(field: str, message: str) -> Rejected:
    return Rejected(
        "validation_error", "Certaines informations ne sont pas valides.", {field: message}
    )


def _is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _uuid(value, field: str) -> uuid.UUID:
    try:
        return uuid.UUID(str(value))
    except (ValueError, TypeError, AttributeError) as exc:
        raise _invalid(field, "Identifiant invalide.") from exc


def _type(value) -> str:
    if value not in TRANSACTION_TYPES:
        raise _invalid("type", "Type inconnu.")
    return value


def _currency(value) -> str:
    if value not in CURRENCIES:
        raise _invalid("currency", "Devise non prise en charge.")
    return value


def max_occurred_on(now: datetime) -> date:
    return now.astimezone(_EARLIEST_ZONE).date() + timedelta(days=MAX_DAYS_AHEAD)


def _owned_category(value, field: str, user) -> Category:
    category_id = _uuid(value, field)
    category = Category.objects.filter(pk=category_id).first()
    if category is None or (category.user_id is not None and category.user_id != user.pk):
        raise Rejected(
            "unknown_category",
            "Cette catégorie n'existe pas sur le serveur.",
            {field: "Catégorie inconnue."},
        )
    return category


def clean_transaction(values: dict, user, now: datetime) -> dict:
    tx_type = _type(values.get("type"))

    amount = values.get("amount")
    if not _is_int(amount):
        raise _invalid("amount", "Le montant doit être un nombre entier.")
    if amount <= 0 or amount > MAX_AMOUNT:
        raise _invalid("amount", "Montant hors limites.")

    category = _owned_category(values.get("category_id"), "category_id", user)
    if category.type != tx_type:
        raise _invalid("category_id", "Cette catégorie ne correspond pas au type d'opération.")

    note = values.get("note")
    if note is not None:
        if not isinstance(note, str):
            raise _invalid("note", "Note invalide.")
        note = note.strip() or None
        if note is not None and len(note) > MAX_NOTE_LENGTH:
            raise _invalid("note", f"La note ne doit pas dépasser {MAX_NOTE_LENGTH} caractères.")

    raw_date = values.get("occurred_on")
    if not isinstance(raw_date, str) or not _DATE_RE.match(raw_date):
        raise _invalid("occurred_on", "Date invalide (format AAAA-MM-JJ).")
    try:
        occurred_on = date.fromisoformat(raw_date)
    except ValueError as exc:
        raise _invalid("occurred_on", "Date invalide.") from exc
    if occurred_on < MIN_DATE or occurred_on > max_occurred_on(now):
        raise _invalid("occurred_on", "Date hors limites.")

    return {
        "type": tx_type,
        "amount": amount,
        "currency": _currency(values.get("currency")),
        "category_id": category.pk,
        "note": note,
        "occurred_on": occurred_on,
    }


def clean_category(values: dict, user, now: datetime) -> dict:
    name = values.get("name")
    if not isinstance(name, str) or not name.strip():
        raise _invalid("name", "Saisis un nom.")
    name = name.strip()
    if len(name) > MAX_CATEGORY_NAME_LENGTH:
        raise _invalid(
            "name", f"Le nom ne doit pas dépasser {MAX_CATEGORY_NAME_LENGTH} caractères."
        )

    icon = values.get("icon")
    if not isinstance(icon, str) or not _ICON_RE.match(icon):
        raise _invalid("icon", "Icône invalide.")

    color = values.get("color")
    if color is not None and (not isinstance(color, str) or not _COLOR_RE.match(color)):
        raise _invalid("color", "Couleur invalide (format #RRGGBB).")

    sort_order = values.get("sort_order", 0)
    if not _is_int(sort_order) or not -1_000_000 <= sort_order <= 1_000_000:
        raise _invalid("sort_order", "Ordre invalide.")

    return {
        "name": name,
        "type": _type(values.get("type")),
        "icon": icon,
        "color": color,
        "sort_order": sort_order,
    }


def clean_budget(values: dict, user, now: datetime) -> dict:
    period = values.get("period")
    if not isinstance(period, str) or not _PERIOD_RE.match(period):
        raise _invalid("period", "Mois invalide (format AAAA-MM).")

    category_id = None
    if values.get("category_id") is not None:
        category = _owned_category(values["category_id"], "category_id", user)
        if category.type != "expense":
            raise _invalid("category_id", "Un budget porte sur une catégorie de dépenses.")
        category_id = category.pk

    limit = values.get("limit_amount")
    if not _is_int(limit) or limit < 0 or limit > MAX_AMOUNT:
        raise _invalid("limit_amount", "Plafond invalide.")

    thresholds = values.get("alert_thresholds", [80, 100])
    if (
        not isinstance(thresholds, list)
        or len(thresholds) > 10
        or not all(_is_int(t) and 1 <= t <= 100 for t in thresholds)
        or len(set(thresholds)) != len(thresholds)
    ):
        raise _invalid("alert_thresholds", "Seuils invalides (entiers de 1 à 100, sans doublon).")

    return {
        "period": period,
        "category_id": category_id,
        "limit_amount": limit,
        "currency": _currency(values.get("currency")),
        "alert_thresholds": sorted(thresholds),
    }
