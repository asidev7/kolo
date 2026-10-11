"""Constantes partagées avec l'application mobile (mêmes valeurs)."""

#: `kMaxAmount` côté mobile : 999 999 999 999 F CFA.
MAX_AMOUNT = 999_999_999_999
#: `kMaxNoteLength` côté mobile.
MAX_NOTE_LENGTH = 140
MAX_CATEGORY_NAME_LENGTH = 40
#: Devises acceptées (`core/constants/currencies.dart`).
CURRENCIES = ("XOF",)
DEFAULT_CURRENCY = "XOF"
TRANSACTION_TYPES = ("expense", "income")
DEFAULT_ALERT_THRESHOLDS = [80, 100]
