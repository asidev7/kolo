import io
from datetime import timedelta

import pytest
from django.core.management import call_command
from django.utils import timezone

from apps.categories.models import Category
from apps.sync.models import ProcessedOperation, SyncCounter
from apps.transactions.models import Transaction

from .conftest import new_id, op, pull, push, tx_data

pytestmark = pytest.mark.django_db


def category(name="Tontine"):
    return {"name": name, "type": "expense", "icon": "other", "color": "#12AB34", "sort_order": 5}


class TestPull:
    def test_requires_authentication(self, api):
        assert pull(api).status_code == 401

    def test_empty_account(self, auth_api):
        body = pull(auth_api).json()
        assert body["changes"] == []
        assert body["next_cursor"] == "0"
        assert body["has_more"] is False
        assert body["server_time"].endswith("Z")

    def test_default_categories_are_not_pulled(self, auth_api):
        """Le téléphone les crée lui-même avec les mêmes UUID."""
        assert pull(auth_api).json()["changes"] == []

    def test_returns_changes_in_api_format(self, auth_api):
        tx_id = new_id()
        push(auth_api, op("transaction", tx_id, tx_data()))
        [change] = pull(auth_api).json()["changes"]
        assert change == {
            "entity": "transaction",
            "entity_id": tx_id,
            "version": 1,
            "server_updated_at": change["server_updated_at"],
            "deleted_at": None,
            "change_seq": 1,
            "data": tx_data(),
        }

    def test_only_own_records(self, auth_api, other_user, client_for):
        push(client_for(other_user), op("transaction", new_id(), tx_data()))
        assert pull(auth_api).json()["changes"] == []

    def test_cursor_resumes_after_last_change(self, auth_api):
        first, second = new_id(), new_id()
        push(auth_api, op("transaction", first, tx_data()))
        cursor = pull(auth_api).json()["next_cursor"]
        push(auth_api, op("transaction", second, tx_data()))
        body = pull(auth_api, cursor=cursor).json()
        assert [c["entity_id"] for c in body["changes"]] == [second]

    def test_record_appears_once_with_latest_state(self, auth_api):
        tx_id = new_id()
        push(auth_api, op("transaction", tx_id, tx_data()))
        push(auth_api, op("transaction", tx_id, tx_data(amount=9), base=1, changed=["amount"]))
        [change] = pull(auth_api).json()["changes"]
        assert change["version"] == 2
        assert change["data"]["amount"] == 9

    def test_tombstones_are_pulled(self, auth_api):
        tx_id = new_id()
        push(auth_api, op("transaction", tx_id, tx_data()))
        cursor = pull(auth_api).json()["next_cursor"]
        push(auth_api, op("transaction", tx_id, op_type="delete", base=1))
        [change] = pull(auth_api, cursor=cursor).json()["changes"]
        assert change["deleted_at"] is not None
        assert change["version"] == 2

    def test_pagination(self, auth_api):
        ids = [new_id() for _ in range(5)]
        push(auth_api, *[op("transaction", i, tx_data()) for i in ids])
        seen, cursor, pages = [], 0, 0
        while True:
            body = pull(auth_api, cursor=cursor, limit=2).json()
            seen += [c["entity_id"] for c in body["changes"]]
            cursor = body["next_cursor"]
            pages += 1
            if not body["has_more"]:
                break
        assert seen == ids
        assert pages == 3

    def test_categories_come_first_in_a_page(self, auth_api):
        cat_id, tx_id = new_id(), new_id()
        push(auth_api, op("category", cat_id, category()))
        push(auth_api, op("transaction", tx_id, tx_data(category_id=cat_id)))
        push(auth_api, op("category", new_id(), category("Cotisation")))
        entities = [c["entity"] for c in pull(auth_api).json()["changes"]]
        assert entities == ["category", "category", "transaction"]

    def test_referenced_category_is_joined_to_the_page(self, auth_api):
        """Catégorie créée (seq 1), utilisée (seq 2), renommée (seq 3) : un
        nouveau téléphone qui lit 1 changement à la fois doit quand même
        recevoir la catégorie avant l'opération qui la référence."""
        cat_id, tx_id = new_id(), new_id()
        push(auth_api, op("category", cat_id, category()))
        push(auth_api, op("transaction", tx_id, tx_data(category_id=cat_id)))
        push(auth_api, op("category", cat_id, category("Tontine 2"), base=1, changed=["name"]))
        body = pull(auth_api, cursor=0, limit=1).json()
        assert [(c["entity"], c["entity_id"]) for c in body["changes"]] == [
            ("category", cat_id),
            ("transaction", tx_id),
        ]
        assert body["changes"][0]["data"]["name"] == "Tontine 2"
        assert body["next_cursor"] == "2"
        assert body["has_more"] is True
        # La page suivante renvoie la catégorie : réappliquer la même version
        # est sans effet côté téléphone.
        nxt = pull(auth_api, cursor=body["next_cursor"], limit=1).json()
        assert [c["entity_id"] for c in nxt["changes"]] == [cat_id]
        assert nxt["has_more"] is False

    @pytest.mark.parametrize("params", [{"cursor": "abc"}, {"cursor": -1}, {"limit": 0}])
    def test_invalid_parameters(self, auth_api, params):
        response = auth_api.get("/api/v1/sync/pull", params)
        assert response.status_code == 400
        assert response.json()["error"]["code"] == "validation_error"

    def test_limit_is_capped(self, auth_api, settings):
        push(auth_api, *[op("transaction", new_id(), tx_data()) for _ in range(3)])
        settings.KOLO_SYNC_PULL_MAX_LIMIT = 2
        body = pull(auth_api, limit=10_000).json()
        assert len(body["changes"]) == 2
        assert body["has_more"] is True

    def test_cursor_ahead_of_server_requires_reset(self, auth_api):
        """Ex. serveur restauré depuis une sauvegarde plus ancienne que le curseur."""
        response = pull(auth_api, cursor=42)
        assert response.status_code == 410
        assert response.json()["error"]["code"] == "cursor_reset_required"


class TestPurge:
    def _age(self, model, pk, days):
        model.objects.filter(pk=pk).update(deleted_at=timezone.now() - timedelta(days=days))

    def test_old_tombstones_are_erased(self, auth_api, user):
        old, recent, alive = new_id(), new_id(), new_id()
        push(auth_api, *[op("transaction", i, tx_data()) for i in (old, recent, alive)])
        push(
            auth_api,
            op("transaction", old, op_type="delete", base=1),
            op("transaction", recent, op_type="delete", base=1),
        )
        self._age(Transaction, old, 91)
        self._age(Transaction, recent, 89)
        call_command("purge_sync_data", stdout=io.StringIO())
        assert set(map(str, Transaction.objects.values_list("pk", flat=True))) == {recent, alive}
        assert SyncCounter.objects.get(user=user).purged_seq == 4

    def test_stale_cursor_must_resync(self, auth_api):
        tx_id = new_id()
        push(auth_api, op("transaction", tx_id, tx_data()))
        stale_cursor = pull(auth_api).json()["next_cursor"]  # "1"
        push(auth_api, op("transaction", tx_id, op_type="delete", base=1))
        self._age(Transaction, tx_id, 120)
        call_command("purge_sync_data", stdout=io.StringIO())
        response = pull(auth_api, cursor=stale_cursor)
        assert response.status_code == 410
        # Un nouveau téléphone (curseur 0) n'est pas concerné.
        assert pull(auth_api, cursor=0).status_code == 200

    def test_category_still_referenced_is_kept(self, auth_api):
        cat_id = new_id()
        push(auth_api, op("category", cat_id, category()))
        push(auth_api, op("transaction", new_id(), tx_data(category_id=cat_id)))
        push(auth_api, op("category", cat_id, op_type="delete", base=1))
        self._age(Category, cat_id, 200)
        call_command("purge_sync_data", stdout=io.StringIO())
        assert Category.objects.filter(pk=cat_id).exists()

    def test_old_processed_operations_are_erased(self, auth_api):
        push(auth_api, op("transaction", new_id(), tx_data()))
        ProcessedOperation.objects.update(created_at=timezone.now() - timedelta(days=91))
        call_command("purge_sync_data", stdout=io.StringIO())
        assert ProcessedOperation.objects.count() == 0
