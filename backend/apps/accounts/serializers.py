import re
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.contrib.auth import password_validation
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers

from .models import User, normalize_email

_CODE_RE = re.compile(r"^\d{6}$")


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "email", "first_name", "timezone"]
        read_only_fields = ["id", "email"]

    def validate_first_name(self, value: str) -> str:
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Saisis ton prénom.")
        return value

    def validate_timezone(self, value: str) -> str:
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError) as exc:
            raise serializers.ValidationError("Fuseau horaire inconnu.") from exc
        return value


class RegisterSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)
    password = serializers.CharField(write_only=True, max_length=128, trim_whitespace=False)
    first_name = serializers.CharField(max_length=60)

    def validate_email(self, value: str) -> str:
        value = normalize_email(value)
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError(
                "Un compte existe déjà avec cette adresse.", code="email_taken"
            )
        return value

    def validate_first_name(self, value: str) -> str:
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Saisis ton prénom.")
        return value

    def validate(self, attrs):
        candidate = User(email=attrs["email"], first_name=attrs["first_name"])
        try:
            password_validation.validate_password(attrs["password"], candidate)
        except DjangoValidationError as exc:
            raise serializers.ValidationError({"password": list(exc.messages)}) from exc
        return attrs

    def create(self, validated_data):
        return User.objects.create_user(**validated_data)


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)
    password = serializers.CharField(write_only=True, max_length=128, trim_whitespace=False)

    def validate_email(self, value: str) -> str:
        return normalize_email(value)


class RefreshSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class ForgotPasswordSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)

    def validate_email(self, value: str) -> str:
        return normalize_email(value)


class ResetPasswordSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)
    code = serializers.CharField(max_length=6)
    new_password = serializers.CharField(max_length=128, trim_whitespace=False)

    def validate_email(self, value: str) -> str:
        return normalize_email(value)

    def validate_code(self, value: str) -> str:
        value = value.strip()
        if not _CODE_RE.match(value):
            raise serializers.ValidationError("Le code contient 6 chiffres.")
        return value


class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(max_length=128, trim_whitespace=False)
    new_password = serializers.CharField(max_length=128, trim_whitespace=False)


def validate_new_password(password: str, user: User) -> None:
    try:
        password_validation.validate_password(password, user)
    except DjangoValidationError as exc:
        raise serializers.ValidationError({"new_password": list(exc.messages)}) from exc
