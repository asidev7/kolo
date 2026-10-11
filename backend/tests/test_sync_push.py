from datetime import timedelta

import pytest
from django.utils import timezone

from apps.categories.models import Category
from apps.sync.models import ProcessedOperation
from apps.transactions.models import Transaction

from .conftest import FOOD, SALARY, new_id, op, push, tx_data

pytestmark = pytest.mark.django_db


class TestEnvelope:
    def test_requires_authentication(self, api):
        response = api.post("/api/v1/sync/push", {"operations": []}, format="json")
        assert response.status_code == 401

    def test_empty_batch(self, auth_api):
        response = auth_api.post("/api/v1/sync/push", {"operations": []}, format="json")
        assert response.status_code == 200
        assert response.json()["results"] == []
        assert response.json()["server_time"].endswith("Z")

    def test_batch_limited_to_100_operations(self, auth_api):
        ops = [op("transaction", new_id(), tx_data()) for _ in range(101)]
        response = auth_api.post("/api/v1/sync/push", {"operations": ops}, format="json")
        assert response.status_code == 400
        assert Transaction.objects.count() == 0

    @pytest.mark.parametrize(
        "mutate",
        [
            lambda o: o.update(op_id="pas-un-uuid"),
            lambda o: o.update(entity_id=None),
            lambda o: o.update(entity="wallet"),
            lambda o: o.update(op_type="patch"),
            lambda o: o.update(base_version=-1),
            lambda o: o.update(base_version=True),
            lambda o: o.update(data=[1, 2]),
            lambda o: o["data"].update(sync_status="synced"),
            lambda o: o.update(changed_fields=["user_id"]),
            lambda o: o.update(changed_fields="amount"),
            lambda o: o.update(data={}),
        ],
    )
    def test_malformed_operation_is_rejected_alone(self, auth_api, mutate):
        bad = op("transaction", new_id(), tx_data())
        mutate(bad)
        good = op("transaction", new_id(), tx_data())
        results = push(auth_api, bad, good)
        assert results[0]["status"] == "rejected"
        assert results[0]["error"]["code"] == "invalid_operation"
        assert results[1]["status"] == "applied"

    def test_non_object_operation(self, auth_api):
        results = push(auth_api, "bonjour")
        assert results[0]["status"] == "rejected"


class TestCreate:
    def test_creates_transaction_with_server_version(self, auth_api, user):
        tx_id = new_id()
        operation = op("transaction", tx_id, tx_data())
        [result] = push(auth_api, operation)
        assert result["op_id"] == operation["op_id"]
        assert result["status"] == "applied"
        assert result["entity"] == "transaction"
        assert result["entity_id"] == tx_id
        assert result["version"] == 1
        assert result["deleted_at"] is None
        assert result["server_updated_at"].endswith("Z")

        row = Transaction.objects.get(pk=tx_id)
        assert row.user == user
        assert row.amount == 1500
        assert row.note == "Zém"
        assert str(row.occurred_on) == "2026-10-09"
        assert row.change_seq == 1
        assert set(row.field_versions) == set(Transaction.SYNC_FIELDS)

    def test_change_seq_is_monotonic_per_account(self, auth_api):
        ids = [new_id() for _ in range(3)]
        push(auth_api, *[op("transaction", i, tx_data()) for i in ids])
        push(auth_api, op("transaction", ids[0], tx_data(amount=2000), base=1, changed=["amount"]))
        seqs = {str(t.pk): t.change_seq for t in Transaction.objects.all()}
        assert seqs == {ids[1]: 2, ids[2]: 3, ids[0]: 4}

    def test_custom_category_then_transaction_in_same_batch(self, auth_api, user):
        cat_id = new_id()
        cat = op(
            "category",
            cat_id,
            {
                "name": "Tontine",
                "type": "expense",
                "icon": "other",
                "color": None,
                "sort_order": 100,
            },
        )
        tx = op("transaction", new_id(), tx_data(category_id=cat_id))
        results = push(auth_api, cat, tx)
        assert [r["status"] for r in results] == ["applied", "applied"]
        category = Category.objects.get(pk=cat_id)
        assert category.user == user
        assert category.is_default is False

    def test_budget(self, auth_api):
        data = {
            "period": "2026-10",
            "category_id": None,
            "limit_amount": 150000,
            "currency": "XOF",
            "alert_thresholds": [80, 100],
        }
        [result] = push(auth_api, op("budget", new_id(), data))
        assert result["status"] == "applied"

    def test_income_with_income_category(self, auth_api):
        [result] = push(
            auth_api, op("transaction", new_id(), tx_data(type="income", category_id=SALARY))
        )
        assert result["status"] == "applied"


class TestValidation:
    @pytest.mark.parametrize(
        ("overrides", "field"),
        [
            ({"amount": 0}, "amount"),
            ({"amount": -5}, "amount"),
            ({"amount": 1_000_000_000_000}, "amount"),
            ({"amount": 15.5}, "amount"),
            ({"amount": "1500"}, "amount"),
            ({"amount": True}, "amount"),
            ({"type": "transfer"}, "type"),
            ({"currency": "EUR"}, "currency"),
            ({"category_id": SALARY}, "category_id"),  # revenu sur une dépense
            ({"note": "x" * 141}, "note"),
            ({"note": 12}, "note"),
            ({"occurred_on": "09/10/2026"}, "occurred_on"),
            ({"occurred_on": "2026-02-30"}, "occurred_on"),
            ({"occurred_on": "2099-01-01"}, "occurred_on"),
            ({"occurred_on": "1999-12-31"}, "occurred_on"),
        ],
    )
    def test_invalid_transaction(self, auth_api, overrides, field):
        [result] = push(auth_api, op("transaction", new_id(), tx_data(**overrides)))
        assert result["status"] == "rejected"
        assert result["error"]["code"] == "validation_error"
        assert field in result["error"]["fields"]
        assert Transaction.objects.count() == 0

    def test_limits_are_inclusive(self, auth_api):
        results = push(
            auth_api,
            op("transaction", new_id(), tx_data(amount=999_999_999_999, note="x" * 140)),
            op("transaction", new_id(), tx_data(amount=1, note=None)),
        )
        assert [r["status"] for r in results] == ["applied", "applied"]

    def test_tomorrow_is_accepted(self, auth_api):
        tomorrow = (timezone.now() + timedelta(days=1)).date().isoformat()
        [result] = push(auth_api, op("transaction", new_id(), tx_data(occurred_on=tomorrow)))
        assert result["status"] == "applied"

    def test_note_is_trimmed_and_blank_becomes_null(self, auth_api):
        tx_id = new_id()
        push(auth_api, op("transaction", tx_id, tx_data(note="   ")))
        assert Transaction.objects.get(pk=tx_id).note is None

    def test_unknown_category(self, auth_api):
        [result] = push(auth_api, op("transaction", new_id(), tx_data(category_id=new_id())))
        assert result["status"] == "rejected"
        assert result["error"]["code"] == "unknown_category"

    def test_category_of_another_account_is_unknown(self, auth_api, other_user, client_for):
        cat_id = new_id()
        push(
            client_for(other_user),
            op("category", cat_id, {"name": "Privé", "type": "expense", "icon": "other"}),
        )
        [result] = push(auth_api, op("transaction", new_id(), tx_data(category_id=cat_id)))
        assert result["error"]["code"] == "unknown_category"

    @pytest.mark.parametrize(
        "data",
        [
            {"name": "", "type": "expense", "icon": "other"},
            {"name": "x" * 41, "type": "expense", "icon": "other"},
            {"name": "Ok", "type": "expense", "icon": "../etc"},
            {"name": "Ok", "type": "expense", "icon": "other", "color": "rouge"},
            {"name": "Ok", "type": "both", "icon": "other"},
        ],
    )
    def test_invalid_category(self, auth_api, data):
        [result] = push(auth_api, op("category", new_id(), data))
        assert result["status"] == "rejected"

    def test_duplicate_category_name_is_rejected(self, auth_api):
        first = op("category", new_id(), {"name": "Tontine", "type": "expense", "icon": "other"})
        second = op("category", new_id(), {"name": "TONTINE ", "type": "expense", "icon": "other"})
        results = push(auth_api, first, second)
        assert results[0]["status"] == "applied"
        assert results[1]["status"] == "rejected"
        assert results[1]["error"]["code"] == "duplicate_name"

    def test_same_category_name_in_two_accounts(self, auth_api, other_user, client_for):
        data = {"name": "Tontine", "type": "expense", "icon": "other"}
        assert push(auth_api, op("category", new_id(), data))[0]["status"] == "applied"
        assert (
            push(client_for(other_user), op("category", new_id(), data))[0]["status"] == "applied"
        )

    @pytest.mark.parametrize(
        "overrides",
        [
            {"period": "2026-13"},
            {"period": "2026-1"},
            {"limit_amount": -1},
            {"alert_thresholds": [0, 100]},
            {"alert_thresholds": [80, 80]},
            {"alert_thresholds": "80,100"},
            {"category_id": SALARY},
        ],
    )
    def test_invalid_budget(self, auth_api, overrides):
        data = {
            "period": "2026-10",
            "category_id": None,
            "limit_amount": 1000,
            "currency": "XOF",
            "alert_thresholds": [80, 100],
        }
        data.update(overrides)
        [result] = push(auth_api, op("budget", new_id(), data))
        assert result["status"] == "rejected"

    def test_second_global_budget_for_same_month_is_rejected(self, auth_api):
        data = {"period": "2026-10", "limit_amount": 1000, "currency": "XOF"}
        results = push(auth_api, op("budget", new_id(), data), op("budget", new_id(), data))
        assert results[1]["status"] == "rejected"
        assert results[1]["error"]["code"] == "duplicate_budget"


class TestIdempotence:
    def test_replayed_operation_is_applied_once(self, auth_api):
        operation = op("transaction", new_id(), tx_data())
        [first] = push(auth_api, operation)
        [second] = push(auth_api, operation)
        assert second["status"] == "duplicate"
        assert second["op_id"] == operation["op_id"]
        assert second["version"] == first["version"]
        assert second["server_updated_at"] == first["server_updated_at"]
        assert Transaction.objects.count() == 1
        assert ProcessedOperation.objects.count() == 1

    def test_replay_returns_version_at_application_time(self, auth_api):
        """Réponse perdue puis renvoi après une autre modification : le client
        doit recevoir la version qu'il a réellement écrite, pas la dernière."""
        tx_id = new_id()
        create = op("transaction", tx_id, tx_data())
        push(auth_api, create)
        push(auth_api, op("transaction", tx_id, tx_data(amount=9), base=1, changed=["amount"]))
        [replay] = push(auth_api, create)
        assert replay["status"] == "duplicate"
        assert replay["version"] == 1
        assert Transaction.objects.get(pk=tx_id).amount == 9

    def test_duplicate_within_same_batch(self, auth_api):
        operation = op("transaction", new_id(), tx_data())
        results = push(auth_api, operation, operation)
        assert [r["status"] for r in results] == ["applied", "duplicate"]

    def test_rejected_operation_is_not_remembered(self, auth_api):
        operation = op("transaction", new_id(), tx_data(category_id=new_id()))
        push(auth_api, operation)
        assert ProcessedOperation.objects.count() == 0

    def test_op_id_of_another_account(self, auth_api, other_user, client_for):
        operation = op("transaction", new_id(), tx_data())
        push(auth_api, operation)
        [result] = push(client_for(other_user), operation)
        assert result["status"] == "rejected"
        assert result["error"]["code"] == "forbidden"


class TestOwnership:
    def test_cannot_touch_record_of_another_account(self, auth_api, other_user, client_for):
        tx_id = new_id()
        push(auth_api, op("transaction", tx_id, tx_data()))
        other = client_for(other_user)
        [update] = push(other, op("transaction", tx_id, tx_data(amount=1), base=1))
        [delete] = push(other, op("transaction", tx_id, op_type="delete", base=1))
        assert update["error"]["code"] == "forbidden"
        assert delete["error"]["code"] == "forbidden"
        row = Transaction.objects.get(pk=tx_id)
        assert row.amount == 1500 and row.deleted_at is None

    def test_default_categories_are_read_only(self, auth_api):
        [rename] = push(
            auth_api,
            op("category", FOOD, {"name": "Nourriture", "type": "expense", "icon": "food"}, base=1),
        )
        [delete] = push(auth_api, op("category", FOOD, op_type="delete", base=1))
        assert rename["error"]["code"] == "read_only"
        assert delete["error"]["code"] == "read_only"
        assert Category.objects.get(pk=FOOD).name == "Alimentation"


class TestUpdateAndDelete:
    def test_update_with_current_base_version(self, auth_api):
        tx_id = new_id()
        push(auth_api, op("transaction", tx_id, tx_data()))
        [result] = push(
            auth_api,
            op(
                "transaction",
                tx_id,
                tx_data(amount=2500, note="Taxi"),
                base=1,
                changed=["amount", "note"],
            ),
        )
        assert result["status"] == "applied"
        assert result["version"] == 2
        row = Transaction.objects.get(pk=tx_id)
        assert (row.amount, row.note) == (2500, "Taxi")
        assert row.field_versions["amount"] == 2
        assert row.field_versions["note"] == 2
        assert row.field_versions["occurred_on"] == 1

    def test_identical_snapshot_does_not_create_a_version(self, auth_api):
        tx_id = new_id()
        push(auth_api, op("transaction", tx_id, tx_data()))
        [result] = push(auth_api, op("transaction", tx_id, tx_data(), base=1))
        assert result["status"] == "applied"
        assert result["version"] == 1

    def test_delete_is_a_tombstone(self, auth_api):
        tx_id = new_id()
        push(auth_api, op("transaction", tx_id, tx_data()))
        [result] = push(auth_api, op("transaction", tx_id, op_type="delete", base=1))
        assert result["status"] == "applied"
        assert result["version"] == 2
        assert result["deleted_at"] is not None
        row = Transaction.objects.get(pk=tx_id)
        assert row.deleted_at is not None
        assert row.amount == 1500  # rien n'est effacé physiquement

    def test_delete_twice(self, auth_api):
        tx_id = new_id()
        push(auth_api, op("transaction", tx_id, tx_data()))
        push(auth_api, op("transaction", tx_id, op_type="delete", base=1))
        [again] = push(auth_api, op("transaction", tx_id, op_type="delete", base=1))
        assert again["status"] == "applied"
        assert again["version"] == 2

    def test_delete_of_unknown_record_is_applied(self, auth_api):
        [result] = push(auth_api, op("transaction", new_id(), op_type="delete", base=0))
        assert result["status"] == "applied"
        assert result["version"] == 0

    def test_base_version_ahead_of_server(self, auth_api):
        tx_id = new_id()
        push(auth_api, op("transaction", tx_id, tx_data()))
        [result] = push(auth_api, op("transaction", tx_id, tx_data(amount=3), base=7))
        assert result["status"] == "rejected"
        assert result["error"]["code"] == "invalid_base_version"

    def test_archived_category_still_usable(self, auth_api):
        cat_id = new_id()
        push(
            auth_api,
            op("category", cat_id, {"name": "Tontine", "type": "expense", "icon": "other"}),
        )
        push(auth_api, op("category", cat_id, op_type="delete", base=1))
        [result] = push(auth_api, op("transaction", new_id(), tx_data(category_id=cat_id)))
        assert result["status"] == "applied"
