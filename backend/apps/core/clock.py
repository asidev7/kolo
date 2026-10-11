"""Horodatages serveur au format de l'application (ARCHITECTURE.md, D11).

ISO-8601 UTC tronqué à la milliseconde, suffixe `Z` : l'ordre des chaînes est
l'ordre chronologique, comme dans la base SQLite du téléphone.
"""

from datetime import UTC, datetime

from django.utils import timezone


def now_ms() -> datetime:
    now = timezone.now()
    return now.replace(microsecond=now.microsecond - now.microsecond % 1000)


def iso_ms(value: datetime | None) -> str | None:
    if value is None:
        return None
    value = value.astimezone(UTC)
    return value.strftime("%Y-%m-%dT%H:%M:%S.") + f"{value.microsecond // 1000:03d}Z"
