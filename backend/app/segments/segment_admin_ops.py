from __future__ import annotations

import json
import csv
import io
from datetime import datetime, timedelta
import os
import subprocess

from flask import Blueprint, jsonify, request, Response
from sqlalchemy import or_

from app.extensions import db
from app.models import (
    AuditLog,
    EscrowTransition,
    Listing,
    Order,
    OrderEvent,
    PaymentIntent,
    PaymentIntentTransition,
    RiskEvent,
    User,
    WalletTxn,
    Wallet,
    WebhookEvent,
    PlatformEvent,
    JobRun,
    NotificationQueue,
    PayoutRequest,
    Shortlet,
    ShortletBooking,
    Referral,
    ListingFavorite,
)
from app.utils.jwt_utils import decode_token, get_bearer_token
from app.utils.autopilot import get_settings
from app.utils.feature_flags import get_all_flags
from app.services.simulation.liquidity_simulator import (
    get_liquidity_baseline,
    run_liquidity_simulation,
)

admin_ops_bp = Blueprint("admin_ops_bp", __name__, url_prefix="/api/admin")


def _current_user() -> User | None:
    token = get_bearer_token(request.headers.get("Authorization", ""))
    if not token:
        return None
    payload = decode_token(token)
    if not payload:
        return None
    sub = payload.get("sub")
    try:
        uid = int(sub)
    except Exception:
        return None
    try:
        return db.session.get(User, uid)
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        return None


def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    role = (getattr(u, "role", None) or "").strip().lower()
    if role == "admin":
        return True
    try:
        return int(getattr(u, "id", 0) or 0) == 1
    except Exception:
        return False


def _require_admin():
    u = _current_user()
    if not u:
        return None, (jsonify({"message": "Unauthorized"}), 401)
    if not _is_admin(u):
        return None, (jsonify({"message": "Forbidden"}), 403)
    return u, None


def _audit(actor_id: int | None, action: str, target_type: str, target_id: int | None, meta: dict | None = None):
    try:
        db.session.add(
            AuditLog(
                actor_user_id=actor_id,
                action=action[:120],
                target_type=target_type[:64],
                target_id=target_id,
                meta=json.dumps(meta or {})[:3000],
            )
        )
        db.session.commit()
    except Exception:
        db.session.rollback()


def _extract_order_id(meta_raw) -> int | None:
    if not meta_raw:
        return None
    try:
        parsed = json.loads(meta_raw) if isinstance(meta_raw, str) else dict(meta_raw)
    except Exception:
        return None
    raw = parsed.get("order_id")
    try:
        return int(raw) if raw is not None else None
    except Exception:
        return None


def _parse_manual_proof(meta_raw) -> dict:
    if not meta_raw:
        return {}
    try:
        parsed = json.loads(meta_raw) if isinstance(meta_raw, str) else dict(meta_raw)
    except Exception:
        return {}
    proof = parsed.get("manual_proof")
    if isinstance(proof, dict):
        return proof
    return {}


def _alembic_head() -> str:
    try:
        from alembic.config import Config
        from alembic.script import ScriptDirectory

        migrations_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "migrations"))
        cfg = Config(os.path.join(migrations_dir, "alembic.ini"))
        cfg.set_main_option("script_location", migrations_dir)
        script = ScriptDirectory.from_config(cfg)
        heads = script.get_heads()
        return heads[0] if heads else "unknown"
    except Exception:
        return "unknown"


def _git_sha() -> str:
    try:
        app_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        out = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=app_root, stderr=subprocess.DEVNULL)
        return out.decode().strip()
    except Exception:
        return (os.getenv("GIT_SHA") or os.getenv("RENDER_GIT_COMMIT") or "unknown").strip() or "unknown"


def _money_to_minor(value) -> int:
    try:
        return int(round(float(value or 0.0) * 100.0))
    except Exception:
        return 0


def _month_floor(dt: datetime) -> datetime:
    return datetime(dt.year, dt.month, 1)


def _month_add(dt: datetime, months: int) -> datetime:
    year = dt.year + (dt.month - 1 + months) // 12
    month = (dt.month - 1 + months) % 12 + 1
    return datetime(year, month, 1)


def _paid_orders(from_dt: datetime | None = None, to_dt: datetime | None = None):
    q = Order.query.filter(
        Order.status.in_(("paid", "merchant_accepted", "driver_assigned", "picked_up", "delivered", "completed"))
    )
    if from_dt is not None:
        q = q.filter(Order.created_at >= from_dt)
    if to_dt is not None:
        q = q.filter(Order.created_at < to_dt)
    return q


def _paid_shortlet_bookings(from_dt: datetime | None = None, to_dt: datetime | None = None):
    q = ShortletBooking.query.filter(ShortletBooking.payment_status == "paid")
    if from_dt is not None:
        q = q.filter(ShortletBooking.created_at >= from_dt)
    if to_dt is not None:
        q = q.filter(ShortletBooking.created_at < to_dt)
    return q


def _analytics_overview_payload() -> dict:
    now = datetime.utcnow()
    users_total = User.query.count()
    merchants_total = User.query.filter(User.role == "merchant").count()
    shortlets_total = Shortlet.query.count()
    orders_q = _paid_orders()
    bookings_q = _paid_shortlet_bookings()
    orders = orders_q.all()
    bookings = bookings_q.all()

    orders_gmv_minor = sum(_money_to_minor(getattr(o, "total_price", None) or getattr(o, "amount", 0.0)) for o in orders)
    shortlet_gmv_minor = sum(_money_to_minor(getattr(b, "total_amount", 0.0)) for b in bookings)
    total_gmv_minor = int(orders_gmv_minor + shortlet_gmv_minor)

    order_commission_minor = sum(
        int(getattr(o, "sale_platform_minor", 0) or 0)
        + int(getattr(o, "delivery_platform_minor", 0) or 0)
        + int(getattr(o, "inspection_platform_minor", 0) or 0)
        for o in orders
    )
    shortlet_commission_minor = sum(
        _money_to_minor(float(getattr(b, "total_amount", 0.0) or 0.0) * 0.05) for b in bookings
    )
    total_commission_minor = int(order_commission_minor + shortlet_commission_minor)

    last_30 = now - timedelta(days=30)
    prev_30 = now - timedelta(days=60)
    current_tx = _paid_orders(last_30, now).count() + _paid_shortlet_bookings(last_30, now).count()
    prev_tx = _paid_orders(prev_30, last_30).count() + _paid_shortlet_bookings(prev_30, last_30).count()
    if prev_tx <= 0:
        monthly_growth_rate = 100.0 if current_tx > 0 else 0.0
    else:
        monthly_growth_rate = round(((current_tx - prev_tx) / prev_tx) * 100.0, 2)

    active_users = set()
    for row in Order.query.filter(Order.created_at >= last_30).all():
        if row.buyer_id:
            active_users.add(int(row.buyer_id))
        if row.merchant_id:
            active_users.add(int(row.merchant_id))
    for row in ShortletBooking.query.filter(ShortletBooking.created_at >= last_30).all():
        if row.user_id:
            active_users.add(int(row.user_id))
    for row in WalletTxn.query.filter(WalletTxn.created_at >= last_30).all():
        if row.user_id:
            active_users.add(int(row.user_id))

    return {
        "ok": True,
        "total_users": int(users_total),
        "total_merchants": int(merchants_total),
        "total_shortlets": int(shortlets_total),
        "total_orders": int(len(orders) + len(bookings)),
        "total_gmv_minor": int(total_gmv_minor),
        "total_commission_minor": int(total_commission_minor),
        "monthly_growth_rate": float(monthly_growth_rate),
        "active_users_last_30_days": int(len(active_users)),
    }


def _analytics_breakdown_payload() -> dict:
    orders = _paid_orders().all()
    bookings = _paid_shortlet_bookings().all()

    declutter_gmv = sum(_money_to_minor(getattr(o, "total_price", None) or getattr(o, "amount", 0.0)) for o in orders)
    shortlet_gmv = sum(_money_to_minor(getattr(b, "total_amount", 0.0)) for b in bookings)
    merchant_gmv = sum(int(getattr(o, "sale_seller_minor", 0) or 0) for o in orders)
    commissions_by_type = {
        "sale_platform_minor": int(sum(int(getattr(o, "sale_platform_minor", 0) or 0) for o in orders)),
        "delivery_platform_minor": int(sum(int(getattr(o, "delivery_platform_minor", 0) or 0) for o in orders)),
        "inspection_platform_minor": int(sum(int(getattr(o, "inspection_platform_minor", 0) or 0) for o in orders)),
        "shortlet_sale_minor": int(sum(_money_to_minor(float(getattr(b, "total_amount", 0.0) or 0.0) * 0.05) for b in bookings)),
    }
    return {
        "ok": True,
        "declutter_gmv": int(declutter_gmv),
        "shortlet_gmv": int(shortlet_gmv),
        "merchant_gmv": int(merchant_gmv),
        "commissions_by_type": commissions_by_type,
    }


@admin_ops_bp.get("/events")
def admin_events():
    _, err = _require_admin()
    if err:
        return err
    event_type = (request.args.get("event_type") or "").strip()
    subject_type = (request.args.get("subject_type") or "").strip()
    subject_id = (request.args.get("subject_id") or "").strip()
    try:
        limit = int(request.args.get("limit") or 50)
    except Exception:
        limit = 50
    limit = max(1, min(limit, 200))
    cursor = (request.args.get("cursor") or "").strip()

    query = PlatformEvent.query
    if event_type:
        query = query.filter_by(event_type=event_type)
    if subject_type:
        query = query.filter_by(subject_type=subject_type)
    if subject_id:
        query = query.filter_by(subject_id=subject_id)
    if cursor:
        try:
            query = query.filter(PlatformEvent.id < int(cursor))
        except Exception:
            pass

    rows = query.order_by(PlatformEvent.id.desc()).limit(limit + 1).all()
    has_more = len(rows) > limit
    rows = rows[:limit]
    next_cursor = str(rows[-1].id) if has_more and rows else None

    return jsonify(
        {
            "ok": True,
            "items": [r.to_dict() for r in rows],
            "next_cursor": next_cursor,
            "has_more": bool(has_more),
            "limit": int(limit),
        }
    ), 200


@admin_ops_bp.get("/events/summary")
def admin_events_summary():
    _, err = _require_admin()
    if err:
        return err
    now = datetime.utcnow()
    cutoff_24h = now - timedelta(hours=24)
    cutoff_7d = now - timedelta(days=7)

    rows_24h = PlatformEvent.query.filter(PlatformEvent.created_at >= cutoff_24h).all()
    rows_7d = PlatformEvent.query.filter(PlatformEvent.created_at >= cutoff_7d).all()
    by_type_24h: dict[str, int] = {}
    by_type_7d: dict[str, int] = {}
    for row in rows_24h:
        key = (row.event_type or "unknown").strip() or "unknown"
        by_type_24h[key] = int(by_type_24h.get(key, 0) + 1)
    for row in rows_7d:
        key = (row.event_type or "unknown").strip() or "unknown"
        by_type_7d[key] = int(by_type_7d.get(key, 0) + 1)
    return jsonify({"ok": True, "last_24h": by_type_24h, "last_7d": by_type_7d}), 200


@admin_ops_bp.get("/health/summary")
def admin_health_summary():
    _, err = _require_admin()
    if err:
        return err
    now = datetime.utcnow()
    settings = get_settings()
    flags = get_all_flags(settings)

    queued = NotificationQueue.query.filter(NotificationQueue.status == "queued")
    failed = NotificationQueue.query.filter(NotificationQueue.status == "failed")
    notify_queue_pending = queued.count()
    notify_queue_failed = failed.count()
    oldest_pending = queued.order_by(NotificationQueue.created_at.asc()).first()
    oldest_pending_age_sec = (
        int((now - oldest_pending.created_at).total_seconds()) if oldest_pending and oldest_pending.created_at else None
    )

    escrow_job = (
        JobRun.query.filter_by(job_name="escrow_runner")
        .order_by(JobRun.ran_at.desc(), JobRun.id.desc())
        .first()
    )
    escrow_runner_last_run_at = escrow_job.ran_at.isoformat() if escrow_job and escrow_job.ran_at else None
    escrow_runner_last_ok = bool(escrow_job.ok) if escrow_job is not None else None
    escrow_runner_last_error = (escrow_job.error or "") if escrow_job else ""

    escrow_pending_settlements_count = Order.query.filter_by(escrow_status="HELD").count()

    payouts_pending_q = PayoutRequest.query.filter_by(status="pending")
    payouts_pending_count = payouts_pending_q.count()
    oldest_payout = payouts_pending_q.order_by(PayoutRequest.created_at.asc()).first()
    payouts_oldest_age_sec = (
        int((now - oldest_payout.created_at).total_seconds()) if oldest_payout and oldest_payout.created_at else None
    )

    cutoff_1h = now - timedelta(hours=1)
    cutoff_24h = now - timedelta(hours=24)
    events_last_1h_errors = PlatformEvent.query.filter(
        PlatformEvent.created_at >= cutoff_1h, PlatformEvent.severity == "ERROR"
    ).count()
    events_last_24h_errors = PlatformEvent.query.filter(
        PlatformEvent.created_at >= cutoff_24h, PlatformEvent.severity == "ERROR"
    ).count()

    payload = {
        "ok": True,
        "server_time": now.isoformat(),
        "git_sha": _git_sha(),
        "alembic_head": _alembic_head(),
        "notify_queue_pending": int(notify_queue_pending),
        "notify_queue_failed": int(notify_queue_failed),
        "oldest_pending_age_sec": oldest_pending_age_sec,
        "escrow_runner_last_run_at": escrow_runner_last_run_at,
        "escrow_runner_last_ok": escrow_runner_last_ok,
        "escrow_runner_last_error": escrow_runner_last_error,
        "escrow_pending_settlements_count": int(escrow_pending_settlements_count),
        "payouts_pending_count": int(payouts_pending_count),
        "payouts_oldest_age_sec": payouts_oldest_age_sec,
        "events_last_1h_errors": int(events_last_1h_errors),
        "events_last_24h_errors": int(events_last_24h_errors),
        "paystack_mode": (getattr(settings, "payments_mode", None) or "mock"),
        "termii_enabled": bool(flags.get("notifications.termii_enabled", False)),
        "cloudinary_enabled": bool(flags.get("media.cloudinary_enabled", False)),
    }
    return jsonify(payload), 200


@admin_ops_bp.get("/search")
def admin_global_search():
    u, err = _require_admin()
    if err:
        return err
    q = (request.args.get("q") or "").strip()
    if not q:
        return jsonify({"ok": True, "query": "", "groups": {"users": [], "orders": [], "listings": [], "payment_intents": [], "escrows": []}}), 200

    like = f"%{q}%"
    users = (
        User.query.filter(
            or_(User.email.ilike(like), User.name.ilike(like), User.phone.ilike(like))
        )
        .order_by(User.id.desc())
        .limit(8)
        .all()
    )
    orders_query = Order.query
    if q.isdigit():
        orders_query = orders_query.filter(or_(Order.id == int(q), Order.buyer_id == int(q), Order.merchant_id == int(q)))
    else:
        orders_query = orders_query.filter(Order.payment_reference.ilike(like))
    orders = orders_query.order_by(Order.id.desc()).limit(8).all()

    listings_query = Listing.query.filter(
        or_(
            Listing.title.ilike(like),
            Listing.description.ilike(like),
            Listing.state.ilike(like),
            Listing.city.ilike(like),
        )
    )
    if q.isdigit():
        listings_query = listings_query.union(Listing.query.filter(Listing.id == int(q)))
    listings = listings_query.order_by(Listing.id.desc()).limit(8).all()

    intents_query = PaymentIntent.query.filter(
        or_(PaymentIntent.reference.ilike(like), PaymentIntent.purpose.ilike(like))
    )
    if q.isdigit():
        intents_query = intents_query.union(PaymentIntent.query.filter(PaymentIntent.id == int(q)))
    intents = intents_query.order_by(PaymentIntent.id.desc()).limit(8).all()

    escrow_rows = (
        Order.query.filter(
            or_(
                Order.escrow_status.ilike(like),
                Order.payment_reference.ilike(like),
            )
        )
        .order_by(Order.id.desc())
        .limit(8)
        .all()
    )
    if q.isdigit():
        try:
            by_id = db.session.get(Order, int(q))
            if by_id and all(int(r.id) != int(by_id.id) for r in escrow_rows):
                escrow_rows = [by_id] + list(escrow_rows)
        except Exception:
            pass

    return jsonify(
        {
            "ok": True,
            "query": q,
            "groups": {
                "users": [
                    {"id": int(r.id), "email": r.email or "", "name": r.name or "", "role": (r.role or "")}
                    for r in users
                ],
                "orders": [
                    {
                        "id": int(r.id),
                        "status": r.status or "",
                        "buyer_id": int(r.buyer_id) if r.buyer_id is not None else None,
                        "merchant_id": int(r.merchant_id) if r.merchant_id is not None else None,
                        "payment_reference": r.payment_reference or "",
                    }
                    for r in orders
                ],
                "listings": [
                    {
                        "id": int(r.id),
                        "title": r.title or "",
                        "state": r.state or "",
                        "city": r.city or "",
                        "user_id": int(r.user_id) if r.user_id is not None else None,
                    }
                    for r in listings
                ],
                "payment_intents": [
                    {
                        "id": int(r.id),
                        "reference": r.reference or "",
                        "status": r.status or "",
                        "purpose": r.purpose or "",
                        "amount": float(r.amount or 0.0),
                    }
                    for r in intents
                ],
                "escrows": [
                    {
                        "id": f"order:{int(r.id)}",
                        "order_id": int(r.id),
                        "escrow_status": (r.escrow_status or "NONE"),
                        "escrow_hold_amount": float(r.escrow_hold_amount or 0.0),
                    }
                    for r in escrow_rows
                ],
            },
        }
    ), 200


@admin_ops_bp.get("/orders/<int:order_id>/timeline")
def admin_order_timeline(order_id: int):
    u, err = _require_admin()
    if err:
        return err
    order = db.session.get(Order, int(order_id))
    if not order:
        return jsonify({"ok": False, "error": "ORDER_NOT_FOUND"}), 404

    events = []

    def _push(ts, kind: str, title: str, meta=None):
        if ts is None:
            ts = datetime.utcnow()
        stamp = ts.isoformat() if hasattr(ts, "isoformat") else str(ts)
        payload = meta or {}
        events.append(
            {
                "timestamp": stamp,
                "type": kind,
                "kind": kind,
                "label": title,
                "title": title,
                "metadata": payload,
                "meta": payload,
            }
        )

    _push(order.created_at, "order", "Order created", {"status": order.status or ""})
    _push(order.updated_at, "order", "Order updated", {"status": order.status or ""})

    for row in OrderEvent.query.filter_by(order_id=int(order.id)).order_by(OrderEvent.created_at.asc()).all():
        _push(row.created_at, "order_event", row.event or "event", {"note": row.note or "", "actor_user_id": row.actor_user_id})

    intents = PaymentIntent.query.filter_by(reference=(order.payment_reference or "")).all() if order.payment_reference else []
    if not intents:
        candidates = PaymentIntent.query.filter_by(purpose="order").order_by(PaymentIntent.created_at.desc()).limit(200).all()
        intents = [row for row in candidates if _extract_order_id(row.meta) == int(order.id)]
    for intent in intents:
        _push(intent.created_at, "payment_intent", "Payment intent created", {"intent_id": int(intent.id), "status": intent.status or "", "reference": intent.reference or ""})
        if intent.paid_at:
            _push(intent.paid_at, "payment_intent", "Payment marked paid", {"intent_id": int(intent.id), "status": intent.status or ""})
        for tr in PaymentIntentTransition.query.filter_by(intent_id=int(intent.id)).order_by(PaymentIntentTransition.created_at.asc()).all():
            _push(tr.created_at, "payment_transition", f"{tr.from_status}->{tr.to_status}", tr.to_dict())

    for wh in WebhookEvent.query.filter_by(reference=(order.payment_reference or "")).order_by(WebhookEvent.created_at.asc()).all():
        _push(wh.created_at, "webhook", f"Webhook {wh.status or 'received'}", {"event_id": wh.event_id, "provider": wh.provider, "error": wh.error or ""})

    for esc in EscrowTransition.query.filter_by(order_id=int(order.id)).order_by(EscrowTransition.created_at.asc()).all():
        _push(esc.created_at, "escrow_transition", f"{esc.from_status}->{esc.to_status}", esc.to_dict())

    txns = WalletTxn.query.filter(WalletTxn.reference.ilike(f"%order:{int(order.id)}%")).order_by(WalletTxn.created_at.asc()).all()
    for txn in txns:
        _push(
            txn.created_at,
            "ledger",
            f"{txn.direction} {txn.kind}",
            {
                "txn_id": int(txn.id),
                "user_id": int(txn.user_id),
                "amount": float(txn.amount or 0.0),
                "reference": txn.reference or "",
            },
        )

    events = sorted(events, key=lambda row: row.get("timestamp") or "")
    return jsonify({"ok": True, "order_id": int(order.id), "items": events}), 200


@admin_ops_bp.get("/payments/intents/<int:intent_id>/transitions")
def admin_payment_intent_transitions(intent_id: int):
    _, err = _require_admin()
    if err:
        return err
    rows = PaymentIntentTransition.query.filter_by(intent_id=int(intent_id)).order_by(PaymentIntentTransition.created_at.asc()).all()
    return jsonify({"ok": True, "items": [r.to_dict() for r in rows]}), 200


@admin_ops_bp.get("/escrows/<int:escrow_id>/transitions")
def admin_escrow_transitions(escrow_id: int):
    _, err = _require_admin()
    if err:
        return err
    rows = EscrowTransition.query.filter(
        or_(
            EscrowTransition.order_id == int(escrow_id),
            EscrowTransition.escrow_id == f"order:{int(escrow_id)}",
        )
    ).order_by(EscrowTransition.created_at.asc()).all()
    return jsonify({"ok": True, "items": [r.to_dict() for r in rows]}), 200


@admin_ops_bp.post("/payments/intents/<int:intent_id>/replay-webhook")
def admin_replay_payment_webhook(intent_id: int):
    u, err = _require_admin()
    if err:
        return err
    intent = db.session.get(PaymentIntent, int(intent_id))
    if not intent:
        return jsonify({"ok": False, "error": "INTENT_NOT_FOUND"}), 404

    row = (
        WebhookEvent.query.filter_by(reference=(intent.reference or ""))
        .filter(WebhookEvent.payload_json.isnot(None))
        .order_by(WebhookEvent.created_at.desc())
        .first()
    )
    if not row or not (row.payload_json or "").strip():
        return jsonify({"ok": False, "error": "WEBHOOK_PAYLOAD_NOT_FOUND"}), 404
    try:
        payload = json.loads(row.payload_json)
    except Exception:
        return jsonify({"ok": False, "error": "INVALID_STORED_PAYLOAD"}), 409

    from app.segments.segment_payments import process_paystack_webhook

    body, status = process_paystack_webhook(
        payload=payload,
        raw=(row.payload_json or "").encode("utf-8"),
        signature=None,
        source=f"admin_replay:{int(intent.id)}",
    )
    _audit(int(u.id), "payment_replay_webhook", "payment_intent", int(intent.id), {"status": status})
    return jsonify(body), int(status)


@admin_ops_bp.post("/orders/<int:order_id>/reconcile")
def admin_reconcile_order(order_id: int):
    u, err = _require_admin()
    if err:
        return err
    order = db.session.get(Order, int(order_id))
    if not order:
        return jsonify({"ok": False, "error": "ORDER_NOT_FOUND"}), 404

    intent = None
    if (order.payment_reference or "").strip():
        intent = PaymentIntent.query.filter_by(reference=order.payment_reference.strip()).first()
    if not intent:
        rows = PaymentIntent.query.filter_by(purpose="order").order_by(PaymentIntent.created_at.desc()).limit(300).all()
        for row in rows:
            if _extract_order_id(row.meta) == int(order.id):
                intent = row
                break

    before = {"order_status": order.status or "", "escrow_status": order.escrow_status or "NONE"}
    updates = {}
    if intent and (intent.status or "").strip().lower() == "paid":
        if (order.status or "").strip().lower() in ("created", "pending", "initialized"):
            order.status = "paid"
            updates["order_status"] = "paid"
        if not (order.payment_reference or "").strip():
            order.payment_reference = intent.reference
            updates["payment_reference"] = intent.reference
    db.session.add(order)
    db.session.commit()

    _audit(int(u.id), "order_reconcile", "order", int(order.id), {"before": before, "updates": updates})
    return jsonify(
        {
            "ok": True,
            "order_id": int(order.id),
            "before": before,
            "after": {"order_status": order.status or "", "escrow_status": order.escrow_status or "NONE"},
            "updates": updates,
            "intent_id": int(intent.id) if intent else None,
        }
    ), 200


@admin_ops_bp.post("/escrows/<int:escrow_id>/reconcile")
def admin_reconcile_escrow(escrow_id: int):
    u, err = _require_admin()
    if err:
        return err
    order = db.session.get(Order, int(escrow_id))
    if not order:
        return jsonify({"ok": False, "error": "ORDER_NOT_FOUND"}), 404
    ref_key = f"order:{int(order.id)}"
    txns = WalletTxn.query.filter(WalletTxn.reference.ilike(f"%{ref_key}%")).all()
    anomaly = None
    if (order.escrow_status or "NONE") == "RELEASED" and len(txns) == 0:
        anomaly = "ESCROW_RELEASED_WITHOUT_LEDGER"
    elif (order.escrow_status or "NONE") == "HELD" and order.escrow_held_at and order.escrow_held_at < datetime.utcnow() - timedelta(days=7):
        anomaly = "ESCROW_HELD_TOO_LONG"
    _audit(
        int(u.id),
        "escrow_reconcile",
        "order",
        int(order.id),
        {"escrow_status": order.escrow_status or "NONE", "ledger_txn_count": len(txns), "anomaly": anomaly},
    )
    return jsonify(
        {
            "ok": True,
            "escrow_id": int(order.id),
            "order_id": int(order.id),
            "escrow_status": order.escrow_status or "NONE",
            "ledger_txn_count": len(txns),
            "anomaly": anomaly,
        }
    ), 200


@admin_ops_bp.get("/anomalies")
def admin_anomalies():
    _, err = _require_admin()
    if err:
        return err
    now = datetime.utcnow()
    try:
        settings = get_settings()
        sla_minutes = int(getattr(settings, "manual_payment_sla_minutes", 360) or 360)
    except Exception:
        sla_minutes = 360
    if sla_minutes < 5:
        sla_minutes = 5
    items = []

    intents = PaymentIntent.query.filter_by(status="paid", purpose="order").order_by(PaymentIntent.created_at.desc()).limit(500).all()
    for intent in intents:
        oid = _extract_order_id(intent.meta)
        if not oid:
            continue
        order = db.session.get(Order, int(oid))
        if not order:
            items.append({"type": "PAID_INTENT_WITHOUT_ORDER", "intent_id": int(intent.id), "reference": intent.reference or ""})
            continue
        status = (order.status or "").strip().lower()
        if status not in ("paid", "merchant_accepted", "driver_assigned", "picked_up", "delivered", "completed"):
            items.append({"type": "PAID_INTENT_UNPAID_ORDER", "order_id": int(order.id), "intent_id": int(intent.id), "order_status": order.status or ""})
        if status in ("paid", "merchant_accepted", "driver_assigned", "picked_up", "delivered", "completed") and (order.escrow_status or "NONE") == "NONE":
            items.append({"type": "PAID_ORDER_UNFUNDED_ESCROW", "order_id": int(order.id), "intent_id": int(intent.id)})

    stale_manual = (
        PaymentIntent.query.filter_by(provider="manual_company_account", purpose="order", status="manual_pending")
        .filter(PaymentIntent.created_at <= now - timedelta(minutes=sla_minutes))
        .order_by(PaymentIntent.created_at.asc())
        .limit(200)
        .all()
    )
    for row in stale_manual:
        proof = _parse_manual_proof(row.meta)
        has_proof = bool((proof.get("bank_txn_reference") or "").strip() or (proof.get("note") or "").strip())
        if has_proof:
            items.append(
                {
                    "type": "MANUAL_PROOF_STALE",
                    "intent_id": int(row.id),
                    "reference": row.reference or "",
                    "created_at": row.created_at.isoformat() if row.created_at else None,
                    "proof_submitted_at": proof.get("submitted_at"),
                }
            )
        else:
            items.append(
                {
                    "type": "MANUAL_PENDING_STALE",
                    "intent_id": int(row.id),
                    "reference": row.reference or "",
                    "created_at": row.created_at.isoformat() if row.created_at else None,
                }
            )

    held_orders = (
        Order.query.filter_by(escrow_status="HELD")
        .filter(Order.escrow_held_at <= now - timedelta(days=7))
        .order_by(Order.escrow_held_at.asc())
        .limit(200)
        .all()
    )
    for row in held_orders:
        items.append({"type": "ESCROW_HELD_TOO_LONG", "order_id": int(row.id), "escrow_held_at": row.escrow_held_at.isoformat() if row.escrow_held_at else None})

    webhook_miss = (
        WebhookEvent.query.filter(WebhookEvent.error.ilike("%INTENT_NOT_FOUND%"))
        .order_by(WebhookEvent.created_at.desc())
        .limit(100)
        .all()
    )
    for row in webhook_miss:
        items.append({"type": "WEBHOOK_WITHOUT_INTENT", "event_id": row.event_id or "", "reference": row.reference or "", "created_at": row.created_at.isoformat() if row.created_at else None})

    return jsonify({"ok": True, "count": len(items), "items": items}), 200


@admin_ops_bp.get("/risk-events")
def admin_risk_events():
    _, err = _require_admin()
    if err:
        return err
    q = (request.args.get("q") or "").strip()
    try:
        min_score = float(request.args.get("min_score") or 0)
    except Exception:
        min_score = 0.0
    try:
        limit = int(request.args.get("limit") or 100)
    except Exception:
        limit = 100
    try:
        offset = int(request.args.get("offset") or 0)
    except Exception:
        offset = 0
    limit = max(1, min(limit, 200))
    offset = max(0, offset)

    query = RiskEvent.query.filter(RiskEvent.score >= float(min_score))
    if q:
        like = f"%{q}%"
        query = query.filter(
            or_(
                RiskEvent.action.ilike(like),
                RiskEvent.reason_code.ilike(like),
                RiskEvent.context_json.ilike(like),
                RiskEvent.request_id.ilike(like),
            )
        )
    total = query.count()
    rows = query.order_by(RiskEvent.created_at.desc()).offset(offset).limit(limit).all()
    return jsonify(
        {"ok": True, "items": [row.to_dict() for row in rows], "total": int(total), "limit": limit, "offset": offset}
    ), 200


@admin_ops_bp.get("/analytics/overview")
def admin_analytics_overview():
    _, err = _require_admin()
    if err:
        return err
    return jsonify(_analytics_overview_payload()), 200


@admin_ops_bp.get("/analytics/revenue-breakdown")
def admin_analytics_revenue_breakdown():
    _, err = _require_admin()
    if err:
        return err
    return jsonify(_analytics_breakdown_payload()), 200


@admin_ops_bp.get("/analytics/projection")
def admin_analytics_projection():
    _, err = _require_admin()
    if err:
        return err
    try:
        months = int(request.args.get("months") or 6)
    except Exception:
        months = 6
    months = max(1, min(months, 24))

    now = datetime.utcnow()
    this_month = _month_floor(now)
    history = []
    for back in range(3, -1, -1):
        start = _month_add(this_month, -back)
        end = _month_add(start, 1)
        orders = _paid_orders(start, end).all()
        bookings = _paid_shortlet_bookings(start, end).all()
        tx_count = int(len(orders) + len(bookings))
        gmv_minor = int(
            sum(_money_to_minor(getattr(o, "total_price", None) or getattr(o, "amount", 0.0)) for o in orders)
            + sum(_money_to_minor(getattr(b, "total_amount", 0.0)) for b in bookings)
        )
        commission_minor = int(
            sum(
                int(getattr(o, "sale_platform_minor", 0) or 0)
                + int(getattr(o, "delivery_platform_minor", 0) or 0)
                + int(getattr(o, "inspection_platform_minor", 0) or 0)
                for o in orders
            )
            + sum(_money_to_minor(float(getattr(b, "total_amount", 0.0) or 0.0) * 0.05) for b in bookings)
        )
        history.append(
            {
                "month": start.strftime("%Y-%m"),
                "transactions": tx_count,
                "gmv_minor": gmv_minor,
                "commission_minor": commission_minor,
            }
        )

    growth_rates = []
    for idx in range(1, len(history)):
        prev = float(history[idx - 1]["gmv_minor"] or 0)
        curr = float(history[idx]["gmv_minor"] or 0)
        if prev > 0:
            growth_rates.append((curr - prev) / prev)
    avg_growth_rate = sum(growth_rates) / len(growth_rates) if growth_rates else 0.0
    if avg_growth_rate < -0.9:
        avg_growth_rate = -0.9
    if avg_growth_rate > 3.0:
        avg_growth_rate = 3.0

    recent = history[-3:] if len(history) >= 3 else history
    recent_tx = sum(int(r["transactions"]) for r in recent)
    recent_gmv = sum(int(r["gmv_minor"]) for r in recent)
    recent_commission = sum(int(r["commission_minor"]) for r in recent)
    avg_order_value_minor = int(round(recent_gmv / recent_tx)) if recent_tx > 0 else 0
    avg_commission_per_tx_minor = int(round(recent_commission / recent_tx)) if recent_tx > 0 else 0

    base_tx = int(history[-1]["transactions"]) if history else 0
    base_gmv = int(history[-1]["gmv_minor"]) if history else 0
    if base_tx <= 0 and avg_order_value_minor > 0:
        base_tx = 1
    projections = []
    for step in range(1, months + 1):
        month_start = _month_add(this_month, step)
        if base_tx > 0:
            projected_tx = max(0, int(round(base_tx * ((1.0 + avg_growth_rate) ** step))))
        else:
            projected_tx = 0
        if avg_order_value_minor > 0:
            projected_gmv_minor = int(projected_tx * avg_order_value_minor)
        else:
            projected_gmv_minor = int(round(base_gmv * ((1.0 + avg_growth_rate) ** step)))
        projected_commission_minor = int(projected_tx * avg_commission_per_tx_minor)
        projections.append(
            {
                "month": month_start.strftime("%Y-%m"),
                "projected_transactions": int(projected_tx),
                "projected_gmv_minor": int(max(projected_gmv_minor, 0)),
                "projected_commission_minor": int(max(projected_commission_minor, 0)),
            }
        )

    return jsonify(
        {
            "ok": True,
            "months": months,
            "assumptions": {
                "average_growth_rate": float(round(avg_growth_rate, 4)),
                "avg_order_value_minor": int(avg_order_value_minor),
                "avg_commission_per_transaction_minor": int(avg_commission_per_tx_minor),
            },
            "history": history,
            "projections": projections,
        }
    ), 200


@admin_ops_bp.get("/analytics/export-csv")
def admin_analytics_export_csv():
    _, err = _require_admin()
    if err:
        return err
    overview = _analytics_overview_payload()
    breakdown = _analytics_breakdown_payload()
    now = datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["section", "metric", "value"])
    for key in (
        "total_users",
        "total_merchants",
        "total_shortlets",
        "total_orders",
        "total_gmv_minor",
        "total_commission_minor",
        "monthly_growth_rate",
        "active_users_last_30_days",
    ):
        writer.writerow(["overview", key, overview.get(key)])
    writer.writerow(["breakdown", "declutter_gmv", breakdown.get("declutter_gmv")])
    writer.writerow(["breakdown", "shortlet_gmv", breakdown.get("shortlet_gmv")])
    writer.writerow(["breakdown", "merchant_gmv", breakdown.get("merchant_gmv")])
    commissions = breakdown.get("commissions_by_type") or {}
    if isinstance(commissions, dict):
        for key, value in commissions.items():
            writer.writerow(["breakdown.commissions_by_type", key, value])
    writer.writerow(["meta", "generated_at", now])
    csv_bytes = output.getvalue()
    return Response(
        csv_bytes,
        mimetype="text/csv",
        headers={
            "Content-Disposition": 'attachment; filename="fliptrybe-analytics.csv"',
            "Cache-Control": "no-store",
        },
    )


@admin_ops_bp.get("/simulation/baseline")
def admin_simulation_baseline():
    _, err = _require_admin()
    if err:
        return err
    payload = get_liquidity_baseline()
    return jsonify(payload), 200


def _parse_simulation_payload(raw: dict) -> dict:
    baseline = get_liquidity_baseline()

    def _as_int(key: str, default: int) -> int:
        try:
            return int(raw.get(key) if raw.get(key) is not None else default)
        except Exception:
            return int(default)

    def _as_float(key: str, default: float) -> float:
        try:
            return float(raw.get(key) if raw.get(key) is not None else default)
        except Exception:
            return float(default)

    return {
        "time_horizon_days": _as_int("time_horizon_days", 90),
        "assumed_daily_gmv_minor": _as_int(
            "assumed_daily_gmv_minor",
            int(baseline.get("avg_daily_gmv_minor") or 0),
        ),
        "assumed_order_count_daily": _as_float(
            "assumed_order_count_daily",
            float(baseline.get("avg_daily_orders") or 0.0),
        ),
        "withdrawal_rate_pct": _as_float(
            "withdrawal_rate_pct",
            float(baseline.get("withdrawal_ratio") or 0.0) * 100.0,
        ),
        "payout_delay_days": _as_int("payout_delay_days", 3),
        "chargeback_rate_pct": _as_float("chargeback_rate_pct", 1.5),
        "operating_cost_daily_minor": _as_int("operating_cost_daily_minor", 0),
        "commission_bps": _as_int("commission_bps", 500),
        "scenario": str(raw.get("scenario") or "base").strip().lower() or "base",
    }


@admin_ops_bp.route("/simulation/liquidity", methods=["GET", "POST"])
def admin_liquidity_simulation():
    _, err = _require_admin()
    if err:
        return err
    payload = request.get_json(silent=True) if request.method == "POST" else None
    if not isinstance(payload, dict):
        payload = request.args.to_dict(flat=True)
    params = _parse_simulation_payload(payload or {})
    result = run_liquidity_simulation(**params)
    return jsonify(result), 200


@admin_ops_bp.get("/simulation/export-csv")
def admin_liquidity_simulation_export_csv():
    _, err = _require_admin()
    if err:
        return err
    params = _parse_simulation_payload(request.args.to_dict(flat=True))
    result = run_liquidity_simulation(**params)
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["day", "gmv_minor", "orders", "commission_minor", "chargebacks_minor", "payouts_minor", "operating_cost_minor", "balance_minor"])
    for row in result.get("series") or []:
        writer.writerow(
            [
                row.get("day"),
                row.get("gmv_minor"),
                row.get("orders"),
                row.get("commission_minor"),
                row.get("chargebacks_minor"),
                row.get("payouts_minor"),
                row.get("operating_cost_minor"),
                row.get("balance_minor"),
            ]
        )
    return Response(
        output.getvalue(),
        mimetype="text/csv",
        headers={
            "Content-Disposition": 'attachment; filename="fliptrybe-liquidity-simulation.csv"',
            "Cache-Control": "no-store",
        },
    )


def _platform_user_id() -> int:
    raw = (os.getenv("PLATFORM_USER_ID") or "").strip()
    if raw.isdigit():
        return int(raw)
    admin = User.query.filter_by(role="admin").order_by(User.id.asc()).first()
    if admin:
        return int(admin.id)
    return 1


@admin_ops_bp.get("/economics/health")
def admin_economics_health():
    _, err = _require_admin()
    if err:
        return err
    now = datetime.utcnow()
    platform_user_id = _platform_user_id()
    platform_wallet = Wallet.query.filter_by(user_id=int(platform_user_id)).first()
    total_platform_wallet_balance_minor = _money_to_minor(
        float(getattr(platform_wallet, "balance", 0.0) or 0.0)
    )

    pending_withdrawals = PayoutRequest.query.filter_by(status="pending").all()
    pending_withdrawals_minor = sum(_money_to_minor(getattr(p, "amount", 0.0)) for p in pending_withdrawals)
    pending_withdrawals_count = len(pending_withdrawals)

    platform_kinds = {"platform_fee", "delivery_commission", "inspection_commission", "shortlet_platform_fee"}
    revenue_last_30_days_minor = 0
    commission_float_minor = 0
    for txn in WalletTxn.query.filter(WalletTxn.user_id == int(platform_user_id)).all():
        sign = 1 if (txn.direction or "").lower() == "credit" else -1
        amt_minor = _money_to_minor(txn.amount)
        if (txn.kind or "").lower() in platform_kinds:
            commission_float_minor += sign * amt_minor
            if txn.created_at and txn.created_at >= now - timedelta(days=30):
                revenue_last_30_days_minor += sign * amt_minor

    return jsonify(
        {
            "ok": True,
            "platform_user_id": int(platform_user_id),
            "total_platform_wallet_balance_minor": int(total_platform_wallet_balance_minor),
            "pending_withdrawals_count": int(pending_withdrawals_count),
            "pending_withdrawals_minor": int(max(pending_withdrawals_minor, 0)),
            "commission_float_minor": int(max(commission_float_minor, 0)),
            "revenue_last_30_days_minor": int(max(revenue_last_30_days_minor, 0)),
        }
    ), 200
