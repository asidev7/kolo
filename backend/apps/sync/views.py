from django.conf import settings
from rest_framework import serializers, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from apps.core.exceptions import ApiError

from . import service


class PushSerializer(serializers.Serializer):
    device_id = serializers.CharField(max_length=64, required=False, allow_blank=True, default="")
    operations = serializers.ListField(
        child=serializers.JSONField(),
        allow_empty=True,
        max_length=settings.KOLO_SYNC_PUSH_MAX_OPERATIONS,
    )


class SyncView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "sync"


class PushView(SyncView):
    """`POST /api/v1/sync/push` — un résultat par opération, dans l'ordre."""

    def post(self, request):
        serializer = PushSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        body = service.push(
            request.user,
            serializer.validated_data["device_id"],
            serializer.validated_data["operations"],
        )
        return Response(body)


class PullView(SyncView):
    """`GET /api/v1/sync/pull?cursor=…&limit=…`."""

    def get(self, request):
        cursor = _int_param(request, "cursor", 0, minimum=0)
        limit = _int_param(request, "limit", settings.KOLO_SYNC_PULL_DEFAULT_LIMIT, minimum=1)
        limit = min(limit, settings.KOLO_SYNC_PULL_MAX_LIMIT)
        try:
            return Response(service.pull(request.user, cursor, limit))
        except service.CursorResetRequired as exc:
            raise ApiError(
                "cursor_reset_required",
                "Synchronisation complète nécessaire.",
                status.HTTP_410_GONE,
            ) from exc


def _int_param(request, name: str, default: int, minimum: int) -> int:
    raw = request.query_params.get(name)
    if raw in (None, ""):
        return default
    try:
        value = int(raw)
    except ValueError as exc:
        raise ApiError("validation_error", f"Paramètre {name} invalide.") from exc
    if value < minimum:
        raise ApiError("validation_error", f"Paramètre {name} invalide.")
    return value
