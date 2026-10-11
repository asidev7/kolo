"""Deux téléphones du même compte modifient le même enregistrement (SYNC.md §5)."""

import pytest

from apps.transactions.models import Transaction

from .conftest import TRANSPORT, new_id, op, push, tx_data

pytestmark = pytest.mark.django_db


@pytest.fixture
def tx_id(auth_api):
    """Opération créée par le téléphone A puis connue de B en version 1."""
    tx_id = new_id()
    push(auth_api, op("transaction", tx_id, tx_data()))
    return tx_id


def edit(client, tx_id, base, device, **fields):
    data = tx_data(**fields)
    return push(
        client, op("transaction", tx_id, data, base=base, changed=list(fields)), device_id=device
    )[0]


class TestFieldMerge:
    def test_different_fields_are_merged(self, auth_api, tx_id):
        a = edit(auth_api, tx_id, 1, "A", amount=2000)
        b = edit(auth_api, tx_id, 1, "B", note="Taxi-moto")
        assert a["status"] == "applied" and a["version"] == 2
        assert b["status"] == "applied" and b["version"] == 3
        row = Transaction.objects.get(pk=tx_id)
        # B a envoyé son instantané complet (montant 1500 connu en v1), mais seul
        # le champ qu'il a modifié est appliqué : la modification de A survit.
        assert (row.amount, row.note) == (2000, "Taxi-moto")

    def test_same_field_is_a_conflict(self, auth_api, tx_id):
        edit(auth_api, tx_id, 1, "A", amount=2000)
        result = edit(auth_api, tx_id, 1, "B", amount=3000)
        assert result["status"] == "conflict"
        assert result["reason"] == "modified_on_server"
        assert result["conflicting_fields"] == ["amount"]
        server = result["server_record"]
        assert server["version"] == 2
        assert server["data"]["amount"] == 2000
        assert server["entity_id"] == tx_id
        assert Transaction.objects.get(pk=tx_id).amount == 2000

    def test_partial_overlap_is_still_a_conflict(self, auth_api, tx_id):
        edit(auth_api, tx_id, 1, "A", note="A")
        result = edit(auth_api, tx_id, 1, "B", amount=3000, note="B")
        assert result["status"] == "conflict"
        assert result["conflicting_fields"] == ["note"]
        row = Transaction.objects.get(pk=tx_id)
        assert (row.amount, row.note) == (1500, "A")  # rien de B n'est appliqué

    def test_keep_mine_after_conflict(self, auth_api, tx_id):
        """« Garder ma version » : nouvel upsert avec base_version = version serveur."""
        edit(auth_api, tx_id, 1, "A", amount=2000)
        conflict = edit(auth_api, tx_id, 1, "B", amount=3000)
        server_version = conflict["server_record"]["version"]
        result = edit(auth_api, tx_id, server_version, "B", amount=3000)
        assert result["status"] == "applied"
        assert Transaction.objects.get(pk=tx_id).amount == 3000

    def test_merged_result_is_validated(self, auth_api, tx_id):
        """A passe en revenu (avec une catégorie de revenu), B change la
        catégorie en Transport : la fusion donnerait un revenu « Transport »."""
        push(
            auth_api,
            op(
                "transaction",
                tx_id,
                tx_data(type="income", category_id="c0a7e9e0-0000-4000-8000-000000000101"),
                base=1,
                changed=["type", "category_id"],
            ),
        )
        result = edit(auth_api, tx_id, 1, "B", category_id=TRANSPORT)
        # category_id a changé des deux côtés : conflit, pas de fusion incohérente.
        assert result["status"] == "conflict"

    def test_old_base_after_several_versions(self, auth_api, tx_id):
        edit(auth_api, tx_id, 1, "A", note="v2")
        edit(auth_api, tx_id, 2, "A", note="v3")
        # Instantané complet de A : sa note est déjà « v3 ».
        push(
            auth_api,
            op(
                "transaction",
                tx_id,
                tx_data(note="v3", occurred_on="2026-10-08"),
                base=3,
                changed=["occurred_on"],
            ),
        )
        result = edit(auth_api, tx_id, 1, "B", amount=4200)
        assert result["status"] == "applied"
        assert result["version"] == 5
        row = Transaction.objects.get(pk=tx_id)
        assert (row.amount, row.note, str(row.occurred_on)) == (4200, "v3", "2026-10-08")

    def test_sequential_edits_from_same_device_never_conflict(self, auth_api, tx_id):
        """Le client « rebase » ses entrées : chaque envoi part de la version reçue."""
        version = 1
        for amount in (2000, 2100, 2200):
            result = edit(auth_api, tx_id, version, "A", amount=amount)
            assert result["status"] == "applied"
            version = result["version"]
        assert version == 4


class TestDeletion:
    def test_delete_wins_over_concurrent_edit(self, auth_api, tx_id):
        push(auth_api, op("transaction", tx_id, op_type="delete", base=1), device_id="A")
        result = edit(auth_api, tx_id, 1, "B", amount=3000)
        assert result["status"] == "conflict"
        assert result["reason"] == "deleted_on_server"
        assert result["server_record"]["deleted_at"] is not None
        assert Transaction.objects.get(pk=tx_id).deleted_at is not None

    def test_explicit_restore(self, auth_api, tx_id):
        [deleted] = push(auth_api, op("transaction", tx_id, op_type="delete", base=1))
        # Le client a vu la suppression (version 2) et choisit de garder sa version.
        result = edit(auth_api, tx_id, deleted["version"], "B", amount=3000)
        assert result["status"] == "applied"
        assert result["deleted_at"] is None
        row = Transaction.objects.get(pk=tx_id)
        assert row.deleted_at is None and row.amount == 3000

    def test_delete_with_stale_base_is_a_conflict(self, auth_api, tx_id):
        edit(auth_api, tx_id, 1, "A", amount=2000)
        [result] = push(auth_api, op("transaction", tx_id, op_type="delete", base=1), device_id="B")
        assert result["status"] == "conflict"
        assert result["conflicting_fields"] == ["amount"]
        assert Transaction.objects.get(pk=tx_id).deleted_at is None
