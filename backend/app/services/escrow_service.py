from __future__ import annotations

import json
from datetime import datetime

from app.extensions import db
from app.models import EscrowTransition, Order


class EscrowStatus:
    NONE = "NONE"
    HELD = "HELD"
    RELEASED = "RELEASED"
    REFUNDED = "REFUNDED"
    DISPUTED = "DISPUTED"

    ALLOWED = {
        NONE: {NONE, HELD},
        HELD: {HELD, RELEASED, REFUNDED, DISPUTED},
        RELEASED: {RELEASED},
        REFUNDED: {REFUNDED},
        DISPUTED: {DISPUTED, RELEASED, REFUNDED},
    }


def _parse_actor(actor) -> tuple[str, int | None]:
    if isinstance(actor, dict):
        actor_type = str(actor.get("type") or "system")
        actor_id_raw = actor.get("id")
        try:
            actor_id = int(actor_id_raw) if actor_id_raw is not None else None
        except Exception:
            actor_id = None
        return actor_type, actor_id
    return "system", None


def transition_escrow(
    order: Order,
    to_state: str,
    *,
    idempotency_key: str,
    actor=None,
    reason: str = "",
    metadata: dict | None = None,
) -> EscrowTransition:
    if order is None:
        raise ValueError("order required")
    key = (idempotency_key or "").strip()
    if not key:
        raise ValueError("idempotency_key required")

    existing = EscrowTransition.query.filter_by(
        order_id=int(order.id), idempotency_key=key[:160]
    ).first()
    if existing:
        return existing

    current = (getattr(order, "escrow_status", None) or EscrowStatus.NONE).strip().upper()
    target = (to_state or EscrowStatus.NONE).strip().upper()
    allowed = EscrowStatus.ALLOWED.get(current, {current})
    if target not in allowed:
        raise ValueError(f"invalid_escrow_transition {current}->{target}")

    actor_type, actor_id = _parse_actor(actor)
    escrow_id = f"order:{int(order.id)}"
    row = EscrowTransition(
        escrow_id=escrow_id,
        order_id=int(order.id),
        from_status=current,
        to_status=target,
        actor_type=actor_type[:32],
        actor_id=actor_id,
        idempotency_key=key[:160],
        reason=(reason or "")[:240],
        metadata_json=json.dumps(metadata or {})[:4000],
        created_at=datetime.utcnow(),
    )
    db.session.add(row)
    db.session.commit()
    return row
