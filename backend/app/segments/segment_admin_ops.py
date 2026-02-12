from __future__ import annotations

import json
from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request
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
    WebhookEvent,
)
from app.utils.jwt_utils import decode_token, get_bearer_token
from app.utils.autopilot import get_settings

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
