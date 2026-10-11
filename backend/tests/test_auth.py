import re

import pytest
from django.core import mail
from rest_framework.throttling import ScopedRateThrottle

from apps.accounts.models import PasswordResetCode, User

from .conftest import PASSWORD

pytestmark = pytest.mark.django_db


def register(api, **overrides):
    body = {"email": "Awa@Example.com ", "password": PASSWORD, "first_name": " Awa "}
    body.update(overrides)
    return api.post("/api/v1/auth/register", body, format="json")


def login(api, email="awa@example.com", password=PASSWORD):
    return api.post("/api/v1/auth/login", {"email": email, "password": password}, format="json")


class TestRegister:
    def test_creates_account_and_returns_session(self, api):
        response = register(api)
        assert response.status_code == 201
        body = response.json()
        assert body["user"]["email"] == "awa@example.com"
        assert body["user"]["first_name"] == "Awa"
        assert body["user"]["timezone"] == "Africa/Porto-Novo"
        assert body["access"] and body["refresh"]
        assert User.objects.get(email="awa@example.com").check_password(PASSWORD)

    def test_email_is_unique_case_insensitively(self, api, user):
        response = register(api, email="AWA@example.com")
        assert response.status_code == 400
        error = response.json()["error"]
        assert error["code"] == "validation_error"
        assert "email" in error["fields"]

    @pytest.mark.parametrize("password", ["court", "12345678901", "password123"])
    def test_rejects_weak_password(self, api, password):
        response = register(api, password=password)
        assert response.status_code == 400
        assert "password" in response.json()["error"]["fields"]

    def test_requires_first_name(self, api):
        response = register(api, first_name="   ")
        assert response.status_code == 400
        assert "first_name" in response.json()["error"]["fields"]

    def test_is_throttled(self, api, monkeypatch):
        monkeypatch.setattr(ScopedRateThrottle, "THROTTLE_RATES", {"auth": "2/min"})
        assert register(api, email="a@example.com").status_code == 201
        assert register(api, email="b@example.com").status_code == 201
        response = register(api, email="c@example.com")
        assert response.status_code == 429
        assert response.json()["error"]["code"] == "throttled"


class TestLogin:
    def test_returns_tokens_usable_on_protected_routes(self, api, user):
        response = login(api, email=" AWA@example.com")
        assert response.status_code == 200
        api.credentials(HTTP_AUTHORIZATION=f"Bearer {response.json()['access']}")
        me = api.get("/api/v1/auth/me")
        assert me.status_code == 200
        assert me.json()["email"] == "awa@example.com"

    def test_wrong_password_gives_generic_error(self, api, user):
        response = login(api, password="mauvais-mot-de-passe")
        assert response.status_code == 401
        assert response.json()["error"]["code"] == "invalid_credentials"

    def test_unknown_email_gives_same_error(self, api):
        response = login(api, email="inconnu@example.com")
        assert response.status_code == 401
        assert response.json()["error"]["code"] == "invalid_credentials"

    def test_inactive_account_cannot_login(self, api, user):
        user.is_active = False
        user.save()
        assert login(api).status_code == 401


class TestTokens:
    def test_protected_route_requires_token(self, api):
        response = api.get("/api/v1/auth/me")
        assert response.status_code == 401
        assert response.json()["error"]["code"] == "not_authenticated"

    def test_invalid_access_token(self, api):
        api.credentials(HTTP_AUTHORIZATION="Bearer abc")
        response = api.get("/api/v1/auth/me")
        assert response.status_code == 401
        assert response.json()["error"]["code"] == "token_not_valid"

    def test_refresh_rotates_and_blacklists_old_token(self, api, user):
        refresh = login(api).json()["refresh"]
        first = api.post("/api/v1/auth/refresh", {"refresh": refresh}, format="json")
        assert first.status_code == 200
        assert first.json()["refresh"] != refresh
        # Réutiliser l'ancien jeton (volé ou rejoué) est refusé.
        replay = api.post("/api/v1/auth/refresh", {"refresh": refresh}, format="json")
        assert replay.status_code == 401
        assert replay.json()["error"]["code"] == "token_not_valid"

    def test_refresh_with_garbage(self, api):
        response = api.post("/api/v1/auth/refresh", {"refresh": "xyz"}, format="json")
        assert response.status_code == 401

    def test_logout_revokes_refresh_token(self, api, user):
        refresh = login(api).json()["refresh"]
        assert (
            api.post("/api/v1/auth/logout", {"refresh": refresh}, format="json").status_code == 204
        )
        response = api.post("/api/v1/auth/refresh", {"refresh": refresh}, format="json")
        assert response.status_code == 401
        # Une seconde déconnexion reste un succès.
        assert (
            api.post("/api/v1/auth/logout", {"refresh": refresh}, format="json").status_code == 204
        )


class TestMe:
    def test_update_first_name_and_timezone(self, auth_api):
        response = auth_api.patch(
            "/api/v1/auth/me", {"first_name": "Awa B.", "timezone": "Africa/Abidjan"}, format="json"
        )
        assert response.status_code == 200
        assert response.json()["first_name"] == "Awa B."
        assert response.json()["timezone"] == "Africa/Abidjan"

    def test_email_is_read_only(self, auth_api, user):
        auth_api.patch("/api/v1/auth/me", {"email": "autre@example.com"}, format="json")
        user.refresh_from_db()
        assert user.email == "awa@example.com"

    def test_rejects_unknown_timezone(self, auth_api):
        response = auth_api.patch("/api/v1/auth/me", {"timezone": "Mars/Olympus"}, format="json")
        assert response.status_code == 400


class TestChangePassword:
    def test_changes_password_and_revokes_other_sessions(self, api, user, client_for):
        other_device_refresh = login(api).json()["refresh"]
        response = client_for(user).post(
            "/api/v1/auth/password/change",
            {"current_password": PASSWORD, "new_password": "Nouveau-mot-2026"},
            format="json",
        )
        assert response.status_code == 200
        assert response.json()["refresh"]
        user.refresh_from_db()
        assert user.check_password("Nouveau-mot-2026")
        replay = api.post("/api/v1/auth/refresh", {"refresh": other_device_refresh}, format="json")
        assert replay.status_code == 401

    def test_requires_current_password(self, auth_api):
        response = auth_api.post(
            "/api/v1/auth/password/change",
            {"current_password": "faux", "new_password": "Nouveau-mot-2026"},
            format="json",
        )
        assert response.status_code == 400
        assert response.json()["error"]["code"] == "invalid_credentials"


def _sent_code() -> str:
    assert len(mail.outbox) == 1
    return re.search(r"\b(\d{6})\b", mail.outbox[0].body).group(1)


class TestPasswordReset:
    def forgot(self, api, email="awa@example.com"):
        return api.post("/api/v1/auth/password/forgot", {"email": email}, format="json")

    def reset(self, api, code, password="Nouveau-mot-2026", email="awa@example.com"):
        return api.post(
            "/api/v1/auth/password/reset",
            {"email": email, "code": code, "new_password": password},
            format="json",
        )

    def test_full_flow(self, api, user):
        old_refresh = login(api).json()["refresh"]
        assert self.forgot(api).status_code == 202
        code = _sent_code()
        assert mail.outbox[0].to == ["awa@example.com"]
        assert self.reset(api, code).status_code == 204
        assert login(api, password="Nouveau-mot-2026").status_code == 200
        # Le code est à usage unique et les anciennes sessions sont révoquées.
        assert self.reset(api, code, password="Encore-autre-2026").status_code == 400
        replay = api.post("/api/v1/auth/refresh", {"refresh": old_refresh}, format="json")
        assert replay.status_code == 401

    def test_unknown_email_looks_identical(self, api):
        response = self.forgot(api, email="inconnu@example.com")
        assert response.status_code == 202
        assert len(mail.outbox) == 0

    def test_code_hash_only_is_stored(self, api, user):
        self.forgot(api)
        code = _sent_code()
        stored = PasswordResetCode.objects.get(user=user)
        assert code not in stored.code_hash

    def test_wrong_code_counts_attempts_then_blocks(self, api, user, settings):
        self.forgot(api)
        code = _sent_code()
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(settings.KOLO_PASSWORD_RESET_MAX_ATTEMPTS):
            response = self.reset(api, wrong)
            assert response.status_code == 400
            assert response.json()["error"]["code"] == "invalid_code"
        # Même le bon code est désormais refusé.
        assert self.reset(api, code).status_code == 400

    def test_new_request_invalidates_previous_code(self, api, user):
        self.forgot(api)
        first = _sent_code()
        mail.outbox.clear()
        self.forgot(api)
        second = _sent_code()
        if first != second:
            assert self.reset(api, first).status_code == 400
        assert self.reset(api, second).status_code == 204

    def test_expired_code(self, api, user):
        self.forgot(api)
        code = _sent_code()
        PasswordResetCode.objects.update(expires_at="2000-01-01T00:00:00Z")
        assert self.reset(api, code).status_code == 400

    def test_weak_new_password_keeps_code_usable(self, api, user):
        self.forgot(api)
        code = _sent_code()
        response = self.reset(api, code, password="123")
        assert response.status_code == 400
        assert "new_password" in response.json()["error"]["fields"]
        assert self.reset(api, code).status_code == 204

    def test_malformed_code(self, api, user):
        assert self.reset(api, "12ab").status_code == 400
