from __future__ import annotations

from datetime import datetime
import json
from typing import Any, Dict, Optional

from app.extensions import db
from app.models.notification import Notification


def queue_in_app(user_id: int, title: str, message: str, meta: Optional[Dict[str, Any]] = None) -> Notification:
    n = Notification(
        user_id=user_id,
        channel="in_app",
        title=title[:160] if title else "",
        message=message or "",
        status="queued",
        provider="local",
        meta=json.dumps(meta or {}),
    )
    db.session.add(n)
    return n


def queue_sms(user_id: int, title: str, message: str, provider: str = "stub", meta: Optional[Dict[str, Any]] = None) -> Notification:
    n = Notification(
        user_id=user_id,
        channel="sms",
        title=title[:160] if title else "",
        message=message or "",
        status="queued",
        provider=provider,
        meta=json.dumps(meta or {}),
    )
    db.session.add(n)
    return n


def queue_whatsapp(user_id: int, title: str, message: str, provider: str = "stub", meta: Optional[Dict[str, Any]] = None) -> Notification:
    n = Notification(
        user_id=user_id,
        channel="whatsapp",
        title=title[:160] if title else "",
        message=message or "",
        status="queued",
        provider=provider,
        meta=json.dumps(meta or {}),
    )
    db.session.add(n)
    return n


def queue_email(user_id: int, title: str, message: str, provider: str = "stub", meta: Optional[Dict[str, Any]] = None) -> Notification:
    n = Notification(
        user_id=user_id,
        channel="email",
        title=title[:160] if title else "",
        message=message or "",
        status="queued",
        provider=provider,
        meta=json.dumps(meta or {}),
    )
    db.session.add(n)
    return n


def mark_sent(n: Notification, provider_ref: str = "") -> None:
    n.status = "sent"
    n.provider_ref = provider_ref[:120] if provider_ref else None
    n.sent_at = datetime.utcnow()
    db.session.add(n)


def mark_failed(n: Notification, provider_ref: str = "") -> None:
    n.status = "failed"
    n.provider_ref = provider_ref[:120] if provider_ref else None
    db.session.add(n)
