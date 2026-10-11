import logging
import time

logger = logging.getLogger("kolo.requests")


class RequestLogMiddleware:
    """Une ligne par requête : méthode, chemin, statut, durée.

    Jamais de corps de requête ou de réponse, de paramètres, d'en-tête
    `Authorization` ni d'adresse e-mail (PRIVACY.md : « les montants et les
    notes ne sont jamais écrits dans les journaux techniques »).
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        started = time.monotonic()
        response = self.get_response(request)
        duration_ms = int((time.monotonic() - started) * 1000)
        level = logging.WARNING if response.status_code >= 500 else logging.INFO
        logger.log(
            level,
            "%s %s %s %dms",
            request.method,
            request.path,
            response.status_code,
            duration_ms,
        )
        return response
