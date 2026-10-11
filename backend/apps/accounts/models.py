import uuid

from django.conf import settings
from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.contrib.auth.models import PermissionsMixin
from django.db import models
from django.utils import timezone as dj_timezone


def normalize_email(email: str) -> str:
    """Adresse entière en minuscules : une seule identité par adresse."""
    return email.strip().lower()


class UserManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, email: str, password: str | None = None, **extra):
        if not email:
            raise ValueError("L'adresse e-mail est obligatoire.")
        user = self.model(email=normalize_email(email), **extra)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email: str, password: str | None = None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        return self.create_user(email, password, **extra)


class User(AbstractBaseUser, PermissionsMixin):
    """Compte KOLO : prénom et adresse e-mail, rien de plus (PRIVACY.md)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(unique=True)
    first_name = models.CharField(max_length=60)
    timezone = models.CharField(max_length=64, default=settings.KOLO_DEFAULT_TIMEZONE)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    date_joined = models.DateTimeField(default=dj_timezone.now)

    objects = UserManager()

    USERNAME_FIELD = "email"
    EMAIL_FIELD = "email"
    REQUIRED_FIELDS = ["first_name"]

    def __str__(self) -> str:
        return str(self.id)


class PasswordResetCode(models.Model):
    """Code à 6 chiffres envoyé par e-mail (mot de passe oublié).

    Seule l'empreinte du code est stockée. Un code est à usage unique, expire
    après `KOLO_PASSWORD_RESET_CODE_MINUTES` et est invalidé après
    `KOLO_PASSWORD_RESET_MAX_ATTEMPTS` essais erronés.
    """

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="reset_codes")
    code_hash = models.CharField(max_length=128)
    created_at = models.DateTimeField(default=dj_timezone.now)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["user", "-created_at"])]

    @property
    def is_usable(self) -> bool:
        return (
            self.used_at is None
            and self.expires_at > dj_timezone.now()
            and self.attempts < settings.KOLO_PASSWORD_RESET_MAX_ATTEMPTS
        )
