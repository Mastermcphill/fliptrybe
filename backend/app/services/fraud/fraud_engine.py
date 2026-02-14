from __future__ import annotations

from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP

from app.extensions import db
from app.models import FraudFlag, Order, PayoutRequest, PlatformEvent, Referral, User, WalletTxn
from app.models.strategic_intelligence import strategic_json_dump
from app.utils.events import log_event


def _to_minor(amount) -> int:
    try:
        value = Decimal(str(amount or 0))
    except Exception:
        value = Decimal("0")
    return int((value * Decimal("100")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _risk_level(score: int) -> str:
    if score >= 80:
        return "freeze"
    if score >= 60:
        return "flag"
    if score >= 30:
        return "monitor"
    return "normal"


def _score_self_referral(user: User) -> tuple[int, dict | None]:
    direct_self = bool(int(getattr(user, "referred_by", 0) or 0) == int(user.id or 0))
    referral_self = Referral.query.filter(
        Referral.referrer_user_id == int(user.id),
        Referral.referred_user_id == int(user.id),
    ).first()
    if direct_self or referral_self:
        return (
            95,
            {
                "code": "SELF_REFERRAL_PATTERN",
                "weight": 95,
                "evidence": {
                    "direct_self_referral": bool(direct_self),
                    "row_present": bool(referral_self is not None),
                },
            },
        )
    return (0, None)


def _score_cancellation_abuse(user_id: int, since: datetime) -> tuple[int, dict | None]:
    cancelled = Order.query.filter(
        Order.created_at >= since,
        Order.status.ilike("cancelled"),
        Order.buyer_id == int(user_id),
    ).count()
    if cancelled < 5:
        return (0, None)
    weight = min(25, int(cancelled * 4))
    return (
        weight,
        {
            "code": "CANCELLATION_ABUSE",
            "weight": weight,
            "evidence": {"cancelled_orders_30d": int(cancelled)},
        },
    )


def _score_refund_ratio(user_id: int, since: datetime) -> tuple[int, dict | None]:
    refunds = WalletTxn.query.filter(
        WalletTxn.user_id == int(user_id),
        WalletTxn.created_at >= since,
        WalletTxn.kind.ilike("%refund%"),
    ).all()
    credits = WalletTxn.query.filter(
        WalletTxn.user_id == int(user_id),
        WalletTxn.created_at >= since,
        WalletTxn.direction == "credit",
    ).all()
    refund_minor = int(sum(abs(_to_minor(getattr(row, "amount", 0.0))) for row in refunds))
    credit_minor = int(sum(abs(_to_minor(getattr(row, "amount", 0.0))) for row in credits))
    if credit_minor <= 0:
        return (0, None)
    ratio = float(refund_minor / float(credit_minor))
    if ratio < 0.25:
        return (0, None)
    weight = 15 if ratio < 0.5 else 25
    return (
        weight,
        {
            "code": "ABNORMAL_REFUND_RATIO",
            "weight": weight,
            "evidence": {
                "refund_minor_30d": refund_minor,
                "credit_minor_30d": credit_minor,
                "ratio": round(ratio, 6),
            },
        },
    )


def _score_wallet_cycling(user_id: int, since: datetime) -> tuple[int, dict | None]:
    txns = WalletTxn.query.filter(
        WalletTxn.user_id == int(user_id),
        WalletTxn.created_at >= since,
    ).order_by(WalletTxn.created_at.desc()).limit(200).all()
    if not txns:
        return (0, None)
    topup_minor = int(
        sum(
            abs(_to_minor(getattr(row, "amount", 0.0)))
            for row in txns
            if (row.direction or "").lower() == "credit" and "topup" in (row.kind or "").lower()
        )
    )
    payout_minor = int(
        sum(
            abs(_to_minor(getattr(row, "amount", 0.0)))
            for row in txns
            if (row.direction or "").lower() == "debit" and "payout" in (row.kind or "").lower()
        )
    )
    if topup_minor <= 0 or payout_minor <= 0:
        return (0, None)
    ratio = float(payout_minor / float(max(1, topup_minor)))
    if ratio < 0.7:
        return (0, None)
    weight = 12 if ratio < 0.9 else 20
    return (
        weight,
        {
            "code": "WALLET_CYCLING_PATTERN",
            "weight": weight,
            "evidence": {
                "topup_minor_7d": int(topup_minor),
                "payout_minor_7d": int(payout_minor),
                "payout_topup_ratio": round(ratio, 6),
            },
        },
    )


def _score_withdrawal_velocity(user_id: int, since: datetime) -> tuple[int, dict | None]:
    rows = PayoutRequest.query.filter(
        PayoutRequest.user_id == int(user_id),
        PayoutRequest.created_at >= since,
    ).all()
    count_24h = int(len(rows))
    if count_24h < 3:
        return (0, None)
    weight = 10 if count_24h < 5 else 20
    return (
        weight,
        {
            "code": "WITHDRAWAL_VELOCITY_SPIKE",
            "weight": weight,
            "evidence": {"payout_requests_24h": count_24h},
        },
    )


def _score_multi_account_bank(user_id: int, since: datetime) -> tuple[int, dict | None]:
    my_accounts = (
        db.session.query(PayoutRequest.account_number)
        .filter(
            PayoutRequest.user_id == int(user_id),
            PayoutRequest.created_at >= since,
            PayoutRequest.account_number.isnot(None),
            PayoutRequest.account_number != "",
        )
        .distinct()
        .all()
    )
    account_numbers = [str(row[0]).strip() for row in my_accounts if str(row[0]).strip()]
    if not account_numbers:
        return (0, None)
    shared_users = (
        db.session.query(PayoutRequest.user_id)
        .filter(PayoutRequest.account_number.in_(account_numbers))
        .distinct()
        .all()
    )
    count_users = len({int(row[0]) for row in shared_users if row[0] is not None})
    if count_users <= 1:
        return (0, None)
    weight = min(35, 10 + (count_users - 1) * 8)
    return (
        weight,
        {
            "code": "MULTI_ACCOUNT_PAYOUT_ACCOUNT",
            "weight": weight,
            "evidence": {
                "shared_account_numbers": account_numbers[:5],
                "distinct_users": int(count_users),
            },
        },
    )


def _score_request_velocity(user_id: int, since: datetime) -> tuple[int, dict | None]:
    events = PlatformEvent.query.filter(
        PlatformEvent.actor_user_id == int(user_id),
        PlatformEvent.created_at >= since,
    ).count()
    if events < 30:
        return (0, None)
    weight = 10 if events < 60 else 18
    return (
        weight,
        {
            "code": "REQUEST_VELOCITY_SPIKE",
            "weight": weight,
            "evidence": {"events_last_hour": int(events)},
        },
    )


def compute_user_fraud_score(user_id: int) -> dict:
    user = db.session.get(User, int(user_id))
    if not user:
        return {
            "ok": False,
            "message": "User not found",
            "user_id": int(user_id),
            "score": 0,
            "level": "normal",
            "reasons": [],
        }
    now = datetime.utcnow()
    since_30d = now - timedelta(days=30)
    since_7d = now - timedelta(days=7)
    since_24h = now - timedelta(hours=24)
    since_1h = now - timedelta(hours=1)

    checks = [
        _score_self_referral(user),
        _score_cancellation_abuse(int(user.id), since_30d),
        _score_refund_ratio(int(user.id), since_30d),
        _score_wallet_cycling(int(user.id), since_7d),
        _score_withdrawal_velocity(int(user.id), since_24h),
        _score_multi_account_bank(int(user.id), since_30d),
        _score_request_velocity(int(user.id), since_1h),
    ]
    reasons = [reason for _, reason in checks if reason is not None]
    score = int(sum(weight for weight, _ in checks))
    if score > 100:
        score = 100
    return {
        "ok": True,
        "user_id": int(user.id),
        "score": int(score),
        "level": _risk_level(score),
        "reasons": reasons,
        "generated_at": now.isoformat(),
    }


def upsert_fraud_flag(
    *,
    user_id: int,
    actor_admin_id: int | None = None,
    persist_clear: bool = True,
) -> dict:
    result = compute_user_fraud_score(int(user_id))
    if not result.get("ok"):
        return result
    score = int(result.get("score") or 0)
    reasons = result.get("reasons") or []
    now = datetime.utcnow()
    active_statuses = ("open", "reviewed", "action_taken")
    latest = (
        FraudFlag.query.filter(
            FraudFlag.user_id == int(user_id),
            FraudFlag.status.in_(active_statuses),
        )
        .order_by(FraudFlag.created_at.desc(), FraudFlag.id.desc())
        .first()
    )

    if score >= 30:
        if latest:
            latest.score = int(score)
            latest.reasons_json = strategic_json_dump({"items": reasons})
            latest.updated_at = now
            db.session.add(latest)
            row = latest
        else:
            row = FraudFlag(
                user_id=int(user_id),
                score=int(score),
                reasons_json=strategic_json_dump({"items": reasons}),
                status="open",
                created_at=now,
                updated_at=now,
            )
            db.session.add(row)
        db.session.commit()
        result["flag"] = row.to_dict()
        log_event(
            "fraud_flag_opened",
            actor_user_id=actor_admin_id,
            subject_type="fraud_flag",
            subject_id=int(row.id),
            idempotency_key=f"fraud_flag_opened:{int(row.id)}:{int(score)}",
            metadata={"user_id": int(user_id), "score": int(score)},
        )
        return result

    if latest and persist_clear:
        latest.status = "cleared"
        latest.reviewed_by_admin_id = int(actor_admin_id) if actor_admin_id is not None else latest.reviewed_by_admin_id
        latest.reviewed_at = now
        latest.updated_at = now
        latest.action_note = "Auto-cleared after deterministic score dropped below threshold."
        db.session.add(latest)
        db.session.commit()
        result["flag"] = latest.to_dict()
    return result


def evaluate_active_fraud_flags(*, window_days: int = 30, max_users: int = 400) -> list[dict]:
    since = datetime.utcnow() - timedelta(days=max(1, min(int(window_days), 90)))
    user_ids: set[int] = set()
    for row in Order.query.filter(Order.created_at >= since).with_entities(Order.buyer_id, Order.merchant_id).all():
        if row[0]:
            user_ids.add(int(row[0]))
        if row[1]:
            user_ids.add(int(row[1]))
    for row in PayoutRequest.query.filter(PayoutRequest.created_at >= since).with_entities(PayoutRequest.user_id).all():
        if row[0]:
            user_ids.add(int(row[0]))
    for row in WalletTxn.query.filter(WalletTxn.created_at >= since).with_entities(WalletTxn.user_id).all():
        if row[0]:
            user_ids.add(int(row[0]))
    for row in Referral.query.filter(Referral.created_at >= since).with_entities(Referral.referrer_user_id, Referral.referred_user_id).all():
        if row[0]:
            user_ids.add(int(row[0]))
        if row[1]:
            user_ids.add(int(row[1]))

    for uid in sorted(user_ids)[: max(1, min(int(max_users), 1000))]:
        try:
            upsert_fraud_flag(user_id=int(uid), persist_clear=True)
        except Exception:
            db.session.rollback()

    rows = (
        FraudFlag.query.filter(FraudFlag.status.in_(("open", "reviewed", "action_taken")))
        .order_by(FraudFlag.score.desc(), FraudFlag.created_at.desc(), FraudFlag.id.desc())
        .limit(500)
        .all()
    )
    return [row.to_dict() for row in rows]


def review_fraud_flag(*, fraud_flag_id: int, admin_id: int, status: str, note: str = "") -> dict:
    row = db.session.get(FraudFlag, int(fraud_flag_id))
    if not row:
        return {"ok": False, "message": "Fraud flag not found"}
    normalized = (status or "").strip().lower()
    if normalized not in ("reviewed", "cleared", "action_taken"):
        return {"ok": False, "message": "status must be reviewed|cleared|action_taken"}
    row.status = normalized
    row.reviewed_by_admin_id = int(admin_id)
    row.reviewed_at = datetime.utcnow()
    row.updated_at = datetime.utcnow()
    row.action_note = (note or "").strip()[:240] or row.action_note
    db.session.add(row)
    db.session.commit()
    log_event(
        "fraud_flag_reviewed",
        actor_user_id=int(admin_id),
        subject_type="fraud_flag",
        subject_id=int(row.id),
        idempotency_key=f"fraud_flag_reviewed:{int(row.id)}:{normalized}:{int(admin_id)}",
        metadata={"status": normalized, "note": row.action_note or ""},
    )
    return {"ok": True, "flag": row.to_dict()}


def freeze_user_for_fraud(*, fraud_flag_id: int, admin_id: int, note: str = "") -> dict:
    row = db.session.get(FraudFlag, int(fraud_flag_id))
    if not row:
        return {"ok": False, "message": "Fraud flag not found"}
    user = db.session.get(User, int(row.user_id))
    if not user:
        return {"ok": False, "message": "User not found"}
    has_is_active_column = False
    try:
        has_is_active_column = "is_active" in set(user.__table__.columns.keys())
    except Exception:
        has_is_active_column = False
    if has_is_active_column and not bool(getattr(user, "is_active", True)):
        row.status = "action_taken"
        row.reviewed_by_admin_id = int(admin_id)
        row.reviewed_at = datetime.utcnow()
        row.updated_at = datetime.utcnow()
        row.action_note = (note or "User already inactive.")[:240]
        db.session.add(row)
        db.session.commit()
        return {"ok": True, "flag": row.to_dict(), "user_id": int(user.id), "already_frozen": True}

    if has_is_active_column:
        setattr(user, "is_active", False)
    row.status = "action_taken"
    row.reviewed_by_admin_id = int(admin_id)
    row.reviewed_at = datetime.utcnow()
    row.updated_at = datetime.utcnow()
    row.action_note = (note or "Account frozen by admin due to fraud risk.")[:240]
    if has_is_active_column:
        db.session.add(user)
    db.session.add(row)
    db.session.commit()
    log_event(
        "fraud_account_frozen",
        actor_user_id=int(admin_id),
        subject_type="user",
        subject_id=int(user.id),
        idempotency_key=f"fraud_account_frozen:{int(user.id)}",
        metadata={"fraud_flag_id": int(row.id), "note": row.action_note or ""},
    )
    return {"ok": True, "flag": row.to_dict(), "user_id": int(user.id), "frozen": True}


def should_block_withdrawal(user_id: int) -> dict:
    row = (
        FraudFlag.query.filter(
            FraudFlag.user_id == int(user_id),
            FraudFlag.status.in_(("open", "reviewed", "action_taken")),
        )
        .order_by(FraudFlag.created_at.desc(), FraudFlag.id.desc())
        .first()
    )
    if row is None:
        score_payload = upsert_fraud_flag(user_id=int(user_id), persist_clear=False)
        row_data = score_payload.get("flag")
        if isinstance(row_data, dict):
            score = int(row_data.get("score") or 0)
            if score >= 80:
                return {"blocked": True, "reason": "High fraud risk", "score": score}
        return {"blocked": False, "reason": ""}
    score = int(row.score or 0)
    if score >= 80 or (row.status or "").strip().lower() == "action_taken":
        return {"blocked": True, "reason": "High fraud risk", "score": score, "fraud_flag_id": int(row.id)}
    return {"blocked": False, "reason": "", "score": score, "fraud_flag_id": int(row.id)}
