import contextlib
import hmac
import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.contrib.auth import authenticate
from django.core.mail import send_mail
from django.db import transaction
from django.utils import timezone
from django.utils.crypto import salted_hmac
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from rest_framework_simplejwt.tokens import RefreshToken

from apps.core.exceptions import ApiError, error_body

from . import serializers
from .models import PasswordResetCode, User

logger = logging.getLogger("kolo.accounts")

_SESSION_EXPIRED = "Ta session a expiré. Connecte-toi à nouveau."


def issue_tokens(user: User) -> dict:
    refresh = RefreshToken.for_user(user)
    return {"access": str(refresh.access_token), "refresh": str(refresh)}


def session_payload(user: User) -> dict:
    return {"user": serializers.UserSerializer(user).data, **issue_tokens(user)}


def revoke_all_sessions(user: User) -> None:
    """Invalide tous les refresh tokens du compte (changement de mot de passe)."""
    for token in OutstandingToken.objects.filter(user=user):
        BlacklistedToken.objects.get_or_create(token=token)


def _hash_code(user: User, code: str) -> str:
    return salted_hmac("kolo.password-reset", f"{user.pk}:{code}").hexdigest()


class AuthThrottled(APIView):
    permission_classes = [AllowAny]
    authentication_classes: list = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"


class RegisterView(AuthThrottled):
    def post(self, request):
        serializer = serializers.RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        logger.info("account created user=%s", user.pk)
        return Response(session_payload(user), status=status.HTTP_201_CREATED)


class LoginView(AuthThrottled):
    def post(self, request):
        serializer = serializers.LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = authenticate(
            request,
            email=serializer.validated_data["email"],
            password=serializer.validated_data["password"],
        )
        if user is None:
            raise ApiError(
                "invalid_credentials",
                "Adresse e-mail ou mot de passe incorrect.",
                status.HTTP_401_UNAUTHORIZED,
            )
        User.objects.filter(pk=user.pk).update(last_login=timezone.now())
        return Response(session_payload(user))


class RefreshView(APIView):
    """Échange un refresh token contre une nouvelle paire (rotation).

    L'ancien refresh token est mis en liste noire : un jeton volé puis réutilisé
    après le téléphone légitime est refusé.
    """

    permission_classes = [AllowAny]
    authentication_classes: list = []

    def post(self, request):
        serializer = serializers.RefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            old = RefreshToken(serializer.validated_data["refresh"])
            user = User.objects.filter(pk=old["user_id"], is_active=True).first()
            if user is None:
                raise TokenError("unknown user")
            old.blacklist()
        except TokenError as exc:
            raise ApiError(
                "token_not_valid", _SESSION_EXPIRED, status.HTTP_401_UNAUTHORIZED
            ) from exc
        return Response(issue_tokens(user))


class LogoutView(APIView):
    permission_classes = [AllowAny]
    authentication_classes: list = []

    def post(self, request):
        serializer = serializers.RefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        # Jeton déjà invalide : la déconnexion est acquise.
        with contextlib.suppress(TokenError):
            RefreshToken(serializer.validated_data["refresh"]).blacklist()
        return Response(status=status.HTTP_204_NO_CONTENT)


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(serializers.UserSerializer(request.user).data)

    def patch(self, request):
        serializer = serializers.UserSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


class ChangePasswordView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"

    def post(self, request):
        serializer = serializers.ChangePasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = request.user
        if not user.check_password(serializer.validated_data["current_password"]):
            raise ApiError(
                "invalid_credentials",
                "Mot de passe actuel incorrect.",
                fields={"current_password": ["Mot de passe actuel incorrect."]},
            )
        serializers.validate_new_password(serializer.validated_data["new_password"], user)
        with transaction.atomic():
            user.set_password(serializer.validated_data["new_password"])
            user.save(update_fields=["password"])
            revoke_all_sessions(user)
        # Les autres appareils sont déconnectés ; celui-ci reçoit une nouvelle session.
        return Response(session_payload(user))


class ForgotPasswordView(APIView):
    """Envoie un code à 6 chiffres. Répond toujours 202, que le compte existe
    ou non, pour ne pas révéler les adresses inscrites."""

    permission_classes = [AllowAny]
    authentication_classes: list = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "password_reset"

    def post(self, request):
        serializer = serializers.ForgotPasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = User.objects.filter(email=serializer.validated_data["email"], is_active=True).first()
        if user is not None:
            self._send_code(user)
        return Response(
            {"message": "Si un compte existe avec cette adresse, un code vient d'y être envoyé."},
            status=status.HTTP_202_ACCEPTED,
        )

    @staticmethod
    def _send_code(user: User) -> None:
        code = f"{secrets.randbelow(1_000_000):06d}"
        minutes = settings.KOLO_PASSWORD_RESET_CODE_MINUTES
        now = timezone.now()
        with transaction.atomic():
            PasswordResetCode.objects.filter(user=user, used_at__isnull=True).update(used_at=now)
            PasswordResetCode.objects.create(
                user=user,
                code_hash=_hash_code(user, code),
                expires_at=now + timedelta(minutes=minutes),
            )
        send_mail(
            subject="KOLO — ton code de réinitialisation",
            message=(
                f"Bonjour {user.first_name},\n\n"
                f"Ton code pour choisir un nouveau mot de passe KOLO : {code}\n"
                f"Il est valable {minutes} minutes.\n\n"
                "Si tu n'as rien demandé, ignore ce message : ton mot de passe ne change pas.\n\n"
                "KOLO — By ASITECH SOLUTION"
            ),
            from_email=None,
            recipient_list=[user.email],
            fail_silently=False,
        )
        logger.info("password reset code sent user=%s", user.pk)


class ResetPasswordView(APIView):
    permission_classes = [AllowAny]
    authentication_classes: list = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "password_reset"

    def post(self, request):
        serializer = serializers.ResetPasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        invalid = ApiError("invalid_code", "Code incorrect ou expiré. Demande un nouveau code.")

        user = User.objects.filter(email=data["email"], is_active=True).first()
        if user is None:
            raise invalid
        with transaction.atomic():
            reset = (
                PasswordResetCode.objects.select_for_update()
                .filter(user=user, used_at__isnull=True)
                .order_by("-created_at")
                .first()
            )
            if reset is None or not reset.is_usable:
                raise invalid
            if not hmac.compare_digest(reset.code_hash, _hash_code(user, data["code"])):
                reset.attempts += 1
                reset.save(update_fields=["attempts"])
                # Répondre sans lever d'exception : la transaction est validée
                # et l'essai erroné reste compté.
                return Response(error_body(invalid.code, invalid.message), status=400)
            serializers.validate_new_password(data["new_password"], user)
            reset.used_at = timezone.now()
            reset.save(update_fields=["used_at"])
            user.set_password(data["new_password"])
            user.save(update_fields=["password"])
            revoke_all_sessions(user)
        logger.info("password reset done user=%s", user.pk)
        return Response(status=status.HTTP_204_NO_CONTENT)
