from __future__ import annotations

import json
from datetime import datetime

from app.extensions import db
from app.models import PaymentIntent, PaymentIntentTransition


class PaymentIntentStatus:
    INITIALIZED = "initialized"
    MANUAL_PENDING = "manual_pending"
    PAID = "paid"
    FAILED = "failed"
    CANCELLED = "cancelled"

    TERMINAL = {PAID, FAILED, CANCELLED}
    ALLOWED = {
        INITIALIZED: {INITIALIZED, MANUAL_PENDING, PAID, FAILED, CANCELLED},
        MANUAL_PENDING: {MANUAL_PENDING, PAID, FAILED, CANCELLED},
        PAID: {PAID},
        FAILED: {FAILED},
        CANCELLED: {CANCELLED},
    }


def _normalize_status(value: str | None) -> str:
    status = (value or "").strip().lower()
    if status == "succeeded":
        return PaymentIntentStatus.PAID
    if status in (
        PaymentIntentStatus.INITIALIZED,
        PaymentIntentStatus.MANUAL_PENDING,
        PaymentIntentStatus.PAID,
        PaymentIntentStatus.FAILED,
        PaymentIntentStatus.CANCELLED,
    ):
        return status
    return PaymentIntentStatus.INITIALIZED


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


def transition_intent(
    intent: PaymentIntent,
    to_state: str,
    *,
    actor=None,
    idempotency_key: str,
    reason: str = "",
    metadata: dict | None = None,
) -> PaymentIntentTransition:
    if intent is None:
        raise ValueError("intent required")
    key = (idempotency_key or "").strip()
    if not key:
        raise ValueError("idempotency_key required")

    existing = PaymentIntentTransition.query.filter_by(
        intent_id=int(intent.id), idempotency_key=key[:160]
    ).first()
    if existing:
        return existing

    current = _normalize_status(getattr(intent, "status", None))
    target = _normalize_status(to_state)
    allowed = PaymentIntentStatus.ALLOWED.get(current, {current})
    if target not in allowed:
        raise ValueError(f"invalid_payment_intent_transition {current}->{target}")

    actor_type, actor_id = _parse_actor(actor)
    row = PaymentIntentTransition(
        intent_id=int(intent.id),
        from_status=current,
        to_status=target,
        actor_type=actor_type[:32],
        actor_id=actor_id,
        idempotency_key=key[:160],
        reason=(reason or "")[:240],
        metadata_json=json.dumps(metadata or {})[:4000],
        created_at=datetime.utcnow(),
    )
    intent.status = target
    intent.updated_at = datetime.utcnow()
    if target == PaymentIntentStatus.PAID and not getattr(intent, "paid_at", None):
        intent.paid_at = datetime.utcnow()
    db.session.add(row)
    db.session.add(intent)
    db.session.commit()
    return row


def is_terminal(intent: PaymentIntent | None) -> bool:
    if not intent:
        return False
    return _normalize_status(getattr(intent, "status", None)) in PaymentIntentStatus.TERMINAL
