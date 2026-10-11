import uuid

import pytest
from django.core.cache import cache
from rest_framework.test import APIClient
from rest_framework.throttling import ScopedRateThrottle

from apps.accounts.models import User

PASSWORD = "Kolo-test-2026!"
FOOD = "c0a7e9e0-0000-4000-8000-000000000001"  # Alimentation (dépense)
TRANSPORT = "c0a7e9e0-0000-4000-8000-000000000002"
SALARY = "c0a7e9e0-0000-4000-8000-000000000101"  # Salaire (revenu)


@pytest.fixture(autouse=True)
def _isolation(monkeypatch):
    cache.clear()
    monkeypatch.setattr(
        ScopedRateThrottle,
        "THROTTLE_RATES",
        {"auth": "1000/min", "password_reset": "1000/min", "sync": "1000/min"},
    )


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def user(db):
    return User.objects.create_user("awa@example.com", PASSWORD, first_name="Awa")


@pytest.fixture
def other_user(db):
    return User.objects.create_user("koffi@example.com", PASSWORD, first_name="Koffi")


@pytest.fixture
def client_for():
    def make(user):
        client = APIClient()
        client.force_authenticate(user)
        return client

    return make


@pytest.fixture
def auth_api(user, client_for):
    return client_for(user)


def new_id() -> str:
    return str(uuid.uuid4())


def tx_data(**overrides) -> dict:
    data = {
        "type": "expense",
        "amount": 1500,
        "currency": "XOF",
        "category_id": FOOD,
        "note": "Zém",
        "occurred_on": "2026-10-09",
    }
    data.update(overrides)
    return data


def op(entity: str, entity_id: str, data=None, *, op_type="upsert", base=0, changed=None):
    data = data or {}
    return {
        "op_id": new_id(),
        "entity": entity,
        "entity_id": entity_id,
        "op_type": op_type,
        "base_version": base,
        "changed_fields": list(data) if changed is None else changed,
        "data": data,
    }


def push(client, *operations, device_id="device-a"):
    response = client.post(
        "/api/v1/sync/push",
        {"device_id": device_id, "operations": list(operations)},
        format="json",
    )
    assert response.status_code == 200, response.content
    return response.json()["results"]


def pull(client, cursor=0, limit=None):
    params = {"cursor": cursor}
    if limit is not None:
        params["limit"] = limit
    return client.get("/api/v1/sync/pull", params)
