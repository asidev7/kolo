"""Protocole de synchronisation côté serveur (docs/SYNC.md).

`push` applique un lot d'opérations de l'outbox ; `pull` renvoie les
changements d'un compte depuis un curseur. Règles clés :

- chaque opération est appliquée **au plus une fois** (`op_id`) ;
- `version` et `server_updated_at` sont attribués ici, jamais par le client ;
- conflit seulement si un champ modifié par le client a aussi changé sur le
  serveur depuis `base_version` (fusion champ par champ via `field_versions`) ;
- une suppression serveur l'emporte sur une modification, sauf si le client
  envoie la modification en connaissant la suppression (`base_version` égale à
  la version du tombstone) : c'est une restauration explicite.
"""

import logging
import uuid
from dataclasses import dataclass
from datetime import datetime

from django.db import IntegrityError, transaction

from apps.budgets.models import Budget
from apps.categories.models import Category
from apps.core.clock import iso_ms, now_ms
from apps.core.models import SyncModel
from apps.transactions.models import Transaction

from . import validation
from .models import ProcessedOperation, SyncCounter
from .validation import Rejected

logger = logging.getLogger("kolo.sync")


@dataclass(frozen=True)
class EntitySpec:
    name: str
    model: type[SyncModel]
    clean: object  # Callable[[dict, User, datetime], dict]
    #: Code renvoyé quand une contrainte d'unicité refuse l'enregistrement.
    duplicate_code: str
    duplicate_message: str


ENTITIES: dict[str, EntitySpec] = {
    "category": EntitySpec(
        "category",
        Category,
        validation.clean_category,
        "duplicate_name",
        "Une catégorie porte déjà ce nom.",
    ),
    "transaction": EntitySpec(
        "transaction",
        Transaction,
        validation.clean_transaction,
        "constraint_violation",
        "Opération refusée par le serveur.",
    ),
    "budget": EntitySpec(
        "budget",
        Budget,
        validation.clean_budget,
        "duplicate_budget",
        "Un budget existe déjà pour ce mois.",
    ),
}

#: Ordre d'application dans une page de pull (clés étrangères d'abord).
PULL_ORDER = ("category", "budget", "transaction")

OP_TYPES = ("upsert", "delete")
DELETED_FIELD = "deleted_at"


# ---------------------------------------------------------------------------
# Représentation
# ---------------------------------------------------------------------------
def record_state(entity: str, record: SyncModel) -> dict:
    """Enregistrement tel que le serveur le connaît (pull et conflits)."""
    return {
        "entity": entity,
        "entity_id": str(record.pk),
        "version": record.version,
        "server_updated_at": iso_ms(record.server_updated_at),
        "deleted_at": iso_ms(record.deleted_at),
        "change_seq": record.change_seq,
        "data": record.sync_data(),
    }


def _comparable(record: SyncModel) -> dict:
    """Valeurs actuelles au format des fonctions `clean_*`."""
    return {field: getattr(record, field) for field in record.SYNC_FIELDS}


# ---------------------------------------------------------------------------
# Push
# ---------------------------------------------------------------------------
class _Context:
    def __init__(self, user, device_id: str, counter: SyncCounter, now: datetime):
        self.user = user
        self.device_id = device_id
        self.counter = counter
        self.now = now

    def next_seq(self) -> int:
        self.counter.last_seq += 1
        return self.counter.last_seq


def push(user, device_id: str, operations: list) -> dict:
    """Applique les opérations dans l'ordre reçu et renvoie un résultat par
    opération. Une opération rejetée n'empêche pas les suivantes."""
    SyncCounter.objects.get_or_create(user=user)
    with transaction.atomic():
        counter = SyncCounter.objects.select_for_update().get(user=user)
        ctx = _Context(user, device_id, counter, now_ms())
        results = [_process(ctx, raw) for raw in operations]
        counter.save(update_fields=["last_seq"])

    stats = {}
    for result in results:
        stats[result["status"]] = stats.get(result["status"], 0) + 1
    logger.info("push user=%s ops=%d %s", user.pk, len(results), stats)
    return {"results": results, "server_time": iso_ms(ctx.now)}


def _result(raw_op_id, status: str, **extra) -> dict:
    return {"op_id": raw_op_id, "status": status, **extra}


def _rejected(raw_op_id, code: str, message: str, fields=None, **extra) -> dict:
    error = {"code": code, "message": message}
    if fields:
        error["fields"] = fields
    return _result(raw_op_id, "rejected", error=error, **extra)


def _process(ctx: _Context, raw) -> dict:
    if not isinstance(raw, dict):
        return _rejected(None, "invalid_operation", "Opération illisible.")
    raw_op_id = raw.get("op_id")
    try:
        op = _parse_envelope(raw)
    except Rejected as exc:
        return _rejected(raw_op_id, exc.code, exc.message, exc.fields)

    ident = {"entity": op["entity"], "entity_id": str(op["entity_id"])}
    processed = ProcessedOperation.objects.filter(op_id=op["op_id"]).first()
    if processed is not None:
        if processed.user_id != ctx.user.pk:
            return _rejected(raw_op_id, "forbidden", "Opération non autorisée.", **ident)
        return {"op_id": raw_op_id, **processed.result, "status": "duplicate"}

    try:
        with transaction.atomic():  # point de sauvegarde par opération
            result = _apply(ctx, op)
            if result["status"] == "applied":
                ProcessedOperation.objects.create(
                    op_id=op["op_id"],
                    user=ctx.user,
                    device_id=ctx.device_id,
                    entity=op["entity"],
                    entity_id=op["entity_id"],
                    result=result,
                )
    except Rejected as exc:
        return _rejected(raw_op_id, exc.code, exc.message, exc.fields, **ident)
    except IntegrityError:
        spec = ENTITIES[op["entity"]]
        return _rejected(raw_op_id, spec.duplicate_code, spec.duplicate_message, **ident)
    return {"op_id": raw_op_id, **result}


def _parse_envelope(raw: dict) -> dict:
    def bad(message: str) -> Rejected:
        return Rejected("invalid_operation", message)

    try:
        op_id = uuid.UUID(str(raw.get("op_id")))
        entity_id = uuid.UUID(str(raw.get("entity_id")))
    except ValueError as exc:
        raise bad("Identifiant d'opération ou d'enregistrement invalide.") from exc

    entity = raw.get("entity")
    if entity not in ENTITIES:
        raise bad("Type d'enregistrement inconnu.")
    op_type = raw.get("op_type")
    if op_type not in OP_TYPES:
        raise bad("Type d'opération inconnu.")
    base_version = raw.get("base_version", 0)
    if not isinstance(base_version, int) or isinstance(base_version, bool) or base_version < 0:
        raise bad("base_version invalide.")

    fields = ENTITIES[entity].model.SYNC_FIELDS
    data = raw.get("data") or {}
    if not isinstance(data, dict):
        raise bad("data doit être un objet.")
    unknown = sorted(set(data) - set(fields))
    if unknown:
        raise bad(f"Champs inconnus : {', '.join(unknown)}.")
    if op_type == "upsert" and not data:
        raise bad("data est obligatoire pour un upsert.")

    changed = raw.get("changed_fields")
    if changed is None:
        changed = list(data)
    if not isinstance(changed, list) or not all(isinstance(f, str) for f in changed):
        raise bad("changed_fields doit être une liste de noms de champs.")
    if set(changed) - set(fields):
        raise bad("changed_fields contient un champ inconnu.")
    if op_type == "upsert" and set(changed) - set(data):
        raise bad("Un champ de changed_fields est absent de data.")

    return {
        "op_id": op_id,
        "entity": entity,
        "entity_id": entity_id,
        "op_type": op_type,
        "base_version": base_version,
        "changed_fields": changed,
        "data": data,
    }


def _apply(ctx: _Context, op: dict) -> dict:
    spec = ENTITIES[op["entity"]]
    record = spec.model.objects.select_for_update().filter(pk=op["entity_id"]).first()

    if record is not None and record.user_id != ctx.user.pk:
        # Catégorie par défaut (user nul) ou enregistrement d'un autre compte.
        if record.user_id is None:
            raise Rejected("read_only", "Les catégories par défaut ne peuvent pas être modifiées.")
        raise Rejected("forbidden", "Enregistrement non autorisé.")

    if op["op_type"] == "delete":
        return _apply_delete(ctx, spec, op, record)
    return _apply_upsert(ctx, spec, op, record)


def _applied(spec: EntitySpec, record: SyncModel) -> dict:
    return {
        "status": "applied",
        "entity": spec.name,
        "entity_id": str(record.pk),
        "version": record.version,
        "server_updated_at": iso_ms(record.server_updated_at),
        "deleted_at": iso_ms(record.deleted_at),
    }


def _conflict(spec: EntitySpec, record: SyncModel, reason: str, fields=()) -> dict:
    return {
        "status": "conflict",
        "entity": spec.name,
        "entity_id": str(record.pk),
        "reason": reason,
        "conflicting_fields": sorted(fields),
        "server_record": record_state(spec.name, record),
    }


def _bump(ctx: _Context, record: SyncModel, changed: set[str]) -> None:
    record.version += 1
    versions = dict(record.field_versions or {})
    for field in changed:
        versions[field] = record.version
    record.field_versions = versions
    record.server_updated_at = ctx.now
    record.updated_at = ctx.now
    record.change_seq = ctx.next_seq()


def _apply_delete(ctx: _Context, spec: EntitySpec, op: dict, record) -> dict:
    if record is None:
        # Jamais arrivé sur le serveur : l'effet voulu (absence) est acquis.
        return {
            "status": "applied",
            "entity": spec.name,
            "entity_id": str(op["entity_id"]),
            "version": 0,
            "server_updated_at": iso_ms(ctx.now),
            "deleted_at": iso_ms(ctx.now),
        }
    if record.deleted_at is not None:
        return _applied(spec, record)
    if op["base_version"] > record.version:
        raise Rejected("invalid_base_version", "Version inconnue du serveur.")
    if op["base_version"] != record.version:
        # Modifié ailleurs depuis : l'utilisateur choisit (SYNC.md §5).
        changed = _changed_since(record, op["base_version"])
        return _conflict(spec, record, "modified_on_server", changed)
    record.deleted_at = ctx.now
    _bump(ctx, record, {DELETED_FIELD})
    record.save()
    return _applied(spec, record)


def _changed_since(record: SyncModel, base_version: int) -> set[str]:
    return {f for f, v in (record.field_versions or {}).items() if v > base_version}


def _apply_upsert(ctx: _Context, spec: EntitySpec, op: dict, record) -> dict:
    data, base = op["data"], op["base_version"]

    if record is None:
        values = spec.clean(data, ctx.user, ctx.now)
        record = spec.model(
            id=op["entity_id"],
            user=ctx.user,
            created_at=ctx.now,
            **values,
        )
        _bump(ctx, record, set(record.SYNC_FIELDS))
        record.save(force_insert=True)
        return _applied(spec, record)

    if base > record.version:
        raise Rejected("invalid_base_version", "Version inconnue du serveur.")

    restoring = False
    if record.deleted_at is not None:
        if base != record.version:
            return _conflict(spec, record, "deleted_on_server", [DELETED_FIELD])
        restoring = True  # le client a vu la suppression et garde sa version

    current = _comparable(record)
    if base == record.version:
        target = {**current, **data}
    else:
        overlap = set(op["changed_fields"]) & _changed_since(record, base)
        if overlap:
            return _conflict(spec, record, "modified_on_server", overlap)
        target = {**current, **{f: data[f] for f in op["changed_fields"]}}

    values = spec.clean(_wire(target), ctx.user, ctx.now)
    changed = {f for f, v in values.items() if current[f] != v}
    if restoring:
        record.deleted_at = None
        changed.add(DELETED_FIELD)
    if not changed:
        return _applied(spec, record)  # rien de nouveau : pas de nouvelle version
    for field, value in values.items():
        setattr(record, field, value)
    _bump(ctx, record, changed)
    record.save()
    return _applied(spec, record)


def _wire(values: dict) -> dict:
    """Remet les valeurs du modèle au format JSON attendu par `clean_*`."""
    out = {}
    for field, value in values.items():
        if isinstance(value, uuid.UUID):
            value = str(value)
        elif hasattr(value, "isoformat") and not isinstance(value, str):
            value = value.isoformat()
        out[field] = value
    return out


# ---------------------------------------------------------------------------
# Pull
# ---------------------------------------------------------------------------
class CursorResetRequired(Exception):  # noqa: N818
    """Le curseur ne peut plus être servi : le client repart de 0."""


def pull(user, cursor: int, limit: int) -> dict:
    counter, _ = SyncCounter.objects.get_or_create(user=user)
    if cursor > counter.last_seq or (0 < cursor < counter.purged_seq):
        raise CursorResetRequired

    candidates: list[tuple[int, str, SyncModel]] = []
    for name in PULL_ORDER:
        model = ENTITIES[name].model
        rows = model.objects.filter(user=user, change_seq__gt=cursor).order_by("change_seq")
        candidates.extend((r.change_seq, name, r) for r in rows[: limit + 1])
    candidates.sort(key=lambda item: item[0])

    has_more = len(candidates) > limit
    page = candidates[:limit]
    next_cursor = page[-1][0] if page else cursor

    # Une opération de cette page peut viser une catégorie modifiée plus tard
    # (change_seq plus grand, donc page suivante) : on la joint dès maintenant
    # pour que la clé étrangère soit satisfaite côté téléphone.
    in_page = {(name, r.pk) for _, name, r in page}
    needed = {
        r.category_id
        for _, name, r in page
        if name in ("transaction", "budget") and r.category_id is not None
    } - {pk for name, pk in in_page if name == "category"}
    extra = []
    if needed:
        extra = list(Category.objects.filter(user=user, pk__in=needed, change_seq__gt=next_cursor))

    by_entity: dict[str, list] = {name: [] for name in PULL_ORDER}
    for record in extra:
        by_entity["category"].append(record)
    for _, name, record in page:
        by_entity[name].append(record)

    changes = [
        record_state(name, record)
        for name in PULL_ORDER
        for record in sorted(by_entity[name], key=lambda r: r.change_seq)
    ]
    return {
        "changes": changes,
        "next_cursor": str(next_cursor),
        "has_more": has_more,
        "server_time": iso_ms(now_ms()),
    }
