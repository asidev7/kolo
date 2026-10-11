"""Format d'erreur unique de l'API.

```json
{"error": {"code": "validation_error", "message": "…", "fields": {"email": ["…"]}}}
```

`code` est stable et destiné au code client ; `message` est en français simple
et peut être affiché tel quel.
"""

from rest_framework import exceptions, status
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

_MESSAGES = {
    "not_authenticated": "Connecte-toi pour continuer.",
    "authentication_failed": "Ta session a expiré. Connecte-toi à nouveau.",
    "token_not_valid": "Ta session a expiré. Connecte-toi à nouveau.",
    "permission_denied": "Cette action n'est pas autorisée.",
    "not_found": "Élément introuvable.",
    "method_not_allowed": "Méthode non autorisée.",
    "throttled": "Trop de tentatives. Réessaie dans quelques minutes.",
    "parse_error": "Requête illisible.",
    "unsupported_media_type": "Format de requête non pris en charge.",
}


class ApiError(exceptions.APIException):
    """Erreur métier avec un code stable."""

    def __init__(self, code: str, message: str, status_code: int = 400, fields=None):
        super().__init__(detail=message, code=code)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.fields = fields


def error_body(code: str, message: str, fields=None) -> dict:
    body = {"code": code, "message": message}
    if fields:
        body["fields"] = fields
    return {"error": body}


def exception_handler(exc, context):
    if isinstance(exc, ApiError):
        return Response(error_body(exc.code, exc.message, exc.fields), status=exc.status_code)

    response = drf_exception_handler(exc, context)
    if response is None:
        return None

    if isinstance(exc, exceptions.ValidationError):
        detail = exc.detail
        fields = detail if isinstance(detail, dict) else {"non_field_errors": detail}
        response.data = error_body(
            "validation_error", "Certaines informations ne sont pas valides.", fields
        )
        return response

    code = getattr(exc, "default_code", "error")
    detail_code = getattr(getattr(exc, "detail", None), "code", None)
    if isinstance(exc.detail, dict) and "code" in exc.detail:
        detail_code = str(exc.detail["code"])
    if detail_code in _MESSAGES:
        code = detail_code
    message = _MESSAGES.get(code, "La requête n'a pas pu être traitée.")
    if response.status_code == status.HTTP_401_UNAUTHORIZED and code not in _MESSAGES:
        code, message = "not_authenticated", _MESSAGES["not_authenticated"]
    response.data = error_body(code, message)
    return response
