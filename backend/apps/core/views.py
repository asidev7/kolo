from django.db import connection
from django.http import JsonResponse
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response

from .clock import iso_ms, now_ms
from .exceptions import error_body


@api_view(["GET"])
@authentication_classes([])
@permission_classes([])
def health(request):
    """Sonde de disponibilité (Docker, Nginx, supervision)."""
    with connection.cursor() as cursor:
        cursor.execute("SELECT 1")
    return Response({"status": "ok", "server_time": iso_ms(now_ms())})


def not_found(request, exception=None):
    return JsonResponse(error_body("not_found", "Élément introuvable."), status=404)


def server_error(request):
    return JsonResponse(
        error_body("server_error", "Le serveur a rencontré un problème. Réessaie plus tard."),
        status=500,
    )
