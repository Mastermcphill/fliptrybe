from __future__ import annotations

import json
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy.exc import IntegrityError

from app.extensions import db
from app.models import PlatformEvent
from app.utils.observability import get_request_id


def _safe_value(value: Any):
    if value is None:
        return None
    if isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, dict):
        return {str(k): _safe_value(v) for k, v in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_safe_value(v) for v in value]
    try:
        return str(value)
    except Exception:
        return "<unserializable>"


def _safe_json(data: Any) -> str:
    normalized = _safe_value(data if isinstance(data, dict) else {"value": data})
    try:
        return json.dumps(normalized, separators=(",", ":"), ensure_ascii=False)
    except Exception:
        try:
            return json.dumps({"raw": str(normalized)})
        except Exception:
            return "{}"


def log_event(
    event_type: str,
    *,
    actor_user_id: int | None = None,
    subject_type: str | None = None,
    subject_id: int | str | None = None,
    severity: str = "INFO",
    request_id: str | None = None,
    idempotency_key: str | None = None,
    metadata: dict | None = None,
) -> PlatformEvent | None:
    """Best-effort event logger.

    Never raises to caller; failures are swallowed by design.
    """
    try:
        if not request_id:
            request_id = get_request_id()
        key = (idempotency_key or "").strip()[:180] or None
        if key:
            existing = PlatformEvent.query.filter_by(idempotency_key=key).first()
            if existing:
                return existing

        event = PlatformEvent(
            event_type=(event_type or "unknown").strip()[:80],
            actor_user_id=int(actor_user_id) if actor_user_id is not None else None,
            subject_type=(subject_type or "").strip()[:80] or None,
            subject_id=str(subject_id)[:120] if subject_id is not None else None,
            request_id=(request_id or "").strip()[:80] or None,
            idempotency_key=key,
            severity=(severity or "INFO").strip().upper()[:16] or "INFO",
            metadata_json=_safe_json(metadata or {}),
        )

        # Nested transaction keeps this logger from breaking parent flows.
        with db.session.begin_nested():
            db.session.add(event)
            db.session.flush()
        return event
    except IntegrityError:
        try:
            db.session.rollback()
        except Exception:
            pass
        if idempotency_key:
            try:
                return PlatformEvent.query.filter_by(idempotency_key=idempotency_key[:180]).first()
            except Exception:
                return None
        return None
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        return None
