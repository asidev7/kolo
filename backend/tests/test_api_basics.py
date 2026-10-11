import logging

import pytest

from .conftest import PASSWORD, new_id, op, push, tx_data

pytestmark = pytest.mark.django_db


def test_health(api):
    response = api.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_unknown_route_returns_json_error(api):
    response = api.get("/api/v1/nope")
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_method_not_allowed(auth_api):
    response = auth_api.get("/api/v1/sync/push")
    assert response.status_code == 405
    assert response.json()["error"]["code"] == "method_not_allowed"


def test_malformed_json(auth_api):
    response = auth_api.generic(
        "POST", "/api/v1/sync/push", "{pas du json", content_type="application/json"
    )
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "parse_error"


def test_logs_never_contain_amounts_notes_or_credentials(api, auth_api, caplog):
    """PRIVACY.md : « les montants et les notes ne sont jamais écrits dans les
    journaux techniques »."""
    caplog.set_level(logging.DEBUG)
    push(auth_api, op("transaction", new_id(), tx_data(amount=987654, note="Pharmacie Zogbo")))
    push(auth_api, op("transaction", new_id(), tx_data(amount=-3, note="Secret refusé")))
    api.post(
        "/api/v1/auth/register",
        {"email": "secret.mail@example.com", "password": PASSWORD, "first_name": "Afi"},
        format="json",
    )
    api.post(
        "/api/v1/auth/login",
        {"email": "secret.mail@example.com", "password": "mauvais"},
        format="json",
    )
    logs = "\n".join(record.getMessage() for record in caplog.records)
    assert "push" in logs  # les journaux existent bien
    for secret in ("987654", "Pharmacie", "Zogbo", "Secret refusé", "secret.mail", PASSWORD):
        assert secret not in logs
