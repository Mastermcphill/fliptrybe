from __future__ import annotations

import json
from datetime import datetime

from app.extensions import db
from app.models import RiskEvent


def evaluate(action: str, *, user=None, context: dict | None = None) -> dict:
    ctx = context or {}
    score = 0.0
    flags: list[str] = []
    decision = "allow"
    reason_code = "OK"

    if action in ("support_message_send", "support_message_spam"):
        repeated = bool(ctx.get("repeated_body"))
        burst = bool(ctx.get("rate_limited"))
        if repeated:
            score += 40.0
            flags.append("REPEATED_BODY")
        if burst:
            score += 45.0
            flags.append("BURST_MESSAGES")
        if score >= 50:
            decision = "throttle"
            reason_code = "SPAM_PATTERN"

    if action in ("payment_initialize", "manual_mark_paid"):
        amount = float(ctx.get("amount") or 0.0)
        if amount > 2000000:
            score += 20.0
            flags.append("HIGH_AMOUNT")
        if bool(ctx.get("amount_mismatch")):
            score += 60.0
            flags.append("AMOUNT_MISMATCH")
            decision = "review"
            reason_code = "PAYMENT_MISMATCH"

    if action in ("listing_create", "listing_update"):
        title = str(ctx.get("title") or "").strip()
        if len(title) < 3:
            score += 20.0
            flags.append("LOW_CONTENT")
        if bool(ctx.get("rate_limited")):
            score += 50.0
            flags.append("BURST_LISTING")
            decision = "throttle"
            reason_code = "LISTING_RATE_LIMIT"

    return {
        "score": min(100.0, float(score)),
        "flags": flags,
        "decision": decision,
        "reason_code": reason_code,
    }


def record_event(
    action: str,
    *,
    user=None,
    context: dict | None = None,
    request_id: str | None = None,
) -> RiskEvent:
    result = evaluate(action, user=user, context=context)
    uid = None
    try:
        uid = int(getattr(user, "id")) if user is not None and getattr(user, "id", None) is not None else None
    except Exception:
        uid = None
    row = RiskEvent(
        action=(action or "unknown")[:80],
        score=float(result["score"]),
        flags_json=json.dumps(result.get("flags") or []),
        decision=(result.get("decision") or "allow")[:64],
        reason_code=(result.get("reason_code") or "OK")[:120],
        user_id=uid,
        request_id=(request_id or "")[:64] or None,
        context_json=json.dumps(context or {})[:4000],
        created_at=datetime.utcnow(),
    )
    db.session.add(row)
    db.session.commit()
    return row
