from __future__ import annotations

import os
import secrets
from datetime import datetime

from sqlalchemy import func

from app.extensions import db
from app.models import Order, Referral, ShortletBooking, User
from app.services.fraud import compute_user_fraud_score, upsert_fraud_flag
from app.utils.events import log_event
from app.utils.wallets import post_txn

_ORDER_SUCCESS_STATUSES = (
    "paid",
    "merchant_accepted",
    "driver_assigned",
    "picked_up",
    "delivered",
    "completed",
)


def _now() -> datetime:
    return datetime.utcnow()


def referral_reward_minor() -> int:
    raw = (os.getenv("REFERRAL_REWARD_MINOR") or "").strip()
    try:
        value = int(raw) if raw else 20000
    except Exception:
        value = 20000
    if value < 0:
        return 0
    return int(value)


def normalize_referral_code(value: str | None) -> str:
    text = (value or "").strip().upper().replace(" ", "")
    return "".join(ch for ch in text if ch.isalnum())[:32]


def ensure_user_referral_code(user: User | None) -> str:
    if not user:
        return ""
    existing = normalize_referral_code(getattr(user, "referral_code", None))
    if existing:
        return existing
    prefix = f"FT{int(user.id):04d}" if getattr(user, "id", None) is not None else "FT"
    for _ in range(20):
        token = f"{prefix}{secrets.token_hex(2).upper()}"[:16]
        taken = User.query.filter(func.upper(User.referral_code) == token).first()
        if taken:
            continue
        user.referral_code = token
        db.session.add(user)
        try:
            db.session.commit()
            return token
        except Exception:
            db.session.rollback()
            continue
    fallback = f"FT{secrets.token_hex(4).upper()}"
    user.referral_code = fallback
    db.session.add(user)
    db.session.commit()
    return fallback


def _successful_transaction_count(user_id: int) -> int:
    orders = (
        Order.query.filter(
            Order.buyer_id == int(user_id),
            Order.status.in_(_ORDER_SUCCESS_STATUSES),
        ).count()
    )
    shortlets = (
        ShortletBooking.query.filter(
            ShortletBooking.user_id == int(user_id),
            ShortletBooking.payment_status == "paid",
        ).count()
    )
    return int(orders or 0) + int(shortlets or 0)


def apply_referral_code(*, user: User | None, code: str | None) -> dict:
    if not user:
        return {"ok": False, "error": "UNAUTHORIZED", "message": "Unauthorized"}
    normalized = normalize_referral_code(code)
    if not normalized:
        return {"ok": False, "error": "INVALID_CODE", "message": "Referral code is required"}
    ensure_user_referral_code(user)
    if int(getattr(user, "referred_by", 0) or 0):
        row = Referral.query.filter_by(referred_user_id=int(user.id)).first()
        return {
            "ok": True,
            "applied": True,
            "message": "Referral already applied",
            "referral": row.to_dict() if row else None,
        }
    if _successful_transaction_count(int(user.id)) > 0:
        return {
            "ok": False,
            "error": "REFERRAL_LOCKED",
            "message": "Referral can only be applied before your first successful transaction.",
        }
    fraud_snapshot = compute_user_fraud_score(int(user.id))
    reasons = fraud_snapshot.get("reasons") if isinstance(fraud_snapshot, dict) else []
    has_self_referral_risk = any(
        isinstance(reason, dict) and (reason.get("code") or "").strip().upper() == "SELF_REFERRAL_PATTERN"
        for reason in (reasons or [])
    )
    if has_self_referral_risk:
        try:
            upsert_fraud_flag(user_id=int(user.id), persist_clear=False)
        except Exception:
            db.session.rollback()
        return {
            "ok": False,
            "error": "FRAUD_SELF_REFERRAL_BLOCKED",
            "message": "Referral request blocked for review due to self-referral risk.",
        }

    referrer = User.query.filter(func.upper(User.referral_code) == normalized).first()
    if not referrer:
        return {"ok": False, "error": "REFERRAL_NOT_FOUND", "message": "Referral code not found"}
    if int(referrer.id) == int(user.id):
        return {"ok": False, "error": "SELF_REFERRAL", "message": "You cannot refer yourself"}

    existing = Referral.query.filter_by(referred_user_id=int(user.id)).first()
    if existing:
        return {
            "ok": True,
            "applied": True,
            "message": "Referral already applied",
            "referral": existing.to_dict(),
        }

    reward_minor = referral_reward_minor()
    row = Referral(
        referrer_user_id=int(referrer.id),
        referred_user_id=int(user.id),
        referral_code=normalized,
        status="pending",
        reward_amount_minor=int(reward_minor),
        created_at=_now(),
    )
    user.referred_by = int(referrer.id)
    db.session.add(row)
    db.session.add(user)
    db.session.commit()
    log_event(
        "referral_applied",
        actor_user_id=int(user.id),
        subject_type="referral",
        subject_id=int(row.id),
        idempotency_key=f"referral_applied:{int(row.id)}",
        metadata={
            "referrer_user_id": int(referrer.id),
            "referred_user_id": int(user.id),
            "referral_code": normalized,
            "reward_amount_minor": int(reward_minor),
        },
    )
    return {
        "ok": True,
        "applied": True,
        "message": "Referral code applied",
        "referral": row.to_dict(),
    }


def maybe_complete_referral_on_success(
    *,
    referred_user_id: int | None,
    source_type: str,
    source_id: int | str,
) -> dict:
    if not referred_user_id:
        return {"ok": True, "completed": False, "reason": "NO_USER"}
    referral = (
        Referral.query.filter_by(referred_user_id=int(referred_user_id))
        .order_by(Referral.id.asc())
        .first()
    )
    if not referral:
        return {"ok": True, "completed": False, "reason": "NO_REFERRAL"}
    if (referral.status or "").strip().lower() == "completed":
        return {"ok": True, "completed": False, "reason": "ALREADY_COMPLETED"}
    if _successful_transaction_count(int(referred_user_id)) < 1:
        return {"ok": True, "completed": False, "reason": "NO_SUCCESS_TRANSACTION"}

    reward_minor = int(referral.reward_amount_minor or referral_reward_minor())
    reward_major = float(reward_minor) / 100.0
    reward_reference = referral.reward_reference or f"referral:{int(referral.id)}"
    txn = post_txn(
        user_id=int(referral.referrer_user_id),
        direction="credit",
        amount=reward_major,
        kind="referral_reward",
        reference=reward_reference,
        note=f"Referral reward for user #{int(referred_user_id)}",
        idempotency_key=f"referral_reward:{int(referral.id)}",
    )
    if txn is None and reward_minor > 0:
        return {"ok": False, "completed": False, "reason": "WALLET_POST_FAILED"}

    referral.status = "completed"
    referral.reward_reference = reward_reference
    referral.completed_at = _now()
    db.session.add(referral)
    db.session.commit()
    log_event(
        "referral_reward_credited",
        actor_user_id=int(referral.referrer_user_id),
        subject_type="referral",
        subject_id=int(referral.id),
        idempotency_key=f"referral_reward_credited:{int(referral.id)}",
        metadata={
            "referred_user_id": int(referred_user_id),
            "reward_amount_minor": int(reward_minor),
            "source_type": source_type,
            "source_id": str(source_id),
            "reward_reference": reward_reference,
        },
    )
    return {
        "ok": True,
        "completed": True,
        "referral_id": int(referral.id),
        "reward_amount_minor": int(reward_minor),
        "reward_reference": reward_reference,
    }


def referral_stats_for_user(user_id: int) -> dict:
    rows = (
        Referral.query.filter_by(referrer_user_id=int(user_id))
        .order_by(Referral.created_at.desc())
        .all()
    )
    joined = len(rows)
    completed_rows = [r for r in rows if (r.status or "").strip().lower() == "completed"]
    completed = len(completed_rows)
    earned_minor = sum(int(r.reward_amount_minor or 0) for r in completed_rows)
    pending = joined - completed
    return {
        "ok": True,
        "joined": int(joined),
        "completed": int(completed),
        "pending": int(pending),
        "earned_minor": int(earned_minor),
    }


def referral_history_for_user(user_id: int, *, limit: int = 50, offset: int = 0) -> dict:
    q = Referral.query.filter_by(referrer_user_id=int(user_id))
    total = q.count()
    rows = (
        q.order_by(Referral.created_at.desc())
        .offset(max(0, int(offset)))
        .limit(max(1, min(int(limit), 200)))
        .all()
    )
    referred_ids = [int(r.referred_user_id) for r in rows if r.referred_user_id is not None]
    users = {}
    if referred_ids:
        items = User.query.filter(User.id.in_(referred_ids)).all()
        users = {int(u.id): u for u in items}
    out = []
    for row in rows:
        referred = users.get(int(row.referred_user_id))
        out.append(
            {
                **row.to_dict(),
                "referred_user": {
                    "id": int(referred.id) if referred else int(row.referred_user_id),
                    "name": (referred.name or "") if referred else "",
                    "email": (referred.email or "") if referred else "",
                },
            }
        )
    return {
        "ok": True,
        "items": out,
        "total": int(total),
        "limit": max(1, min(int(limit), 200)),
        "offset": max(0, int(offset)),
    }
