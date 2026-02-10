from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP

from flask import Blueprint, jsonify, request, current_app

from app.extensions import db
from app.models import AuditLog, User, PaymentIntent, WebhookEvent, Order
from app.utils.jwt_utils import decode_token
from app.utils.paystack_client import verify_signature
from app.utils.wallets import post_txn
from app.utils.autopilot import get_settings
from app.utils.idempotency import lookup_response, store_response
from app.integrations.common import IntegrationDisabledError, IntegrationMisconfiguredError
from app.integrations.payments.factory import build_payments_provider

payments_bp = Blueprint("payments_bp", __name__, url_prefix="/api/payments")

_INIT = False


@payments_bp.before_app_request
def _ensure_tables_once():
    global _INIT
    if _INIT:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _INIT = True


def _bearer():
    h = request.headers.get("Authorization", "")
    if not h.startswith("Bearer "):
        return None
    return h.replace("Bearer ", "", 1).strip()


def _current_user():
    tok = _bearer()
    if not tok:
        return None
    payload = decode_token(tok)
    if not payload:
        return None
    sub = payload.get("sub")
    if not sub:
        return None
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
    if getattr(u, "is_admin", False):
        return True
    try:
        return int(u.id or 0) == 1
    except Exception:
        return False


def _json_decimal(v) -> Decimal:
    return Decimal(str(v or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _json_float(v) -> float:
    return float(_json_decimal(v))


def _order_is_paid(order: Order) -> bool:
    status = (getattr(order, "status", "") or "").strip().lower()
    return status in ("paid", "merchant_accepted", "driver_assigned", "picked_up", "delivered", "completed")


def _order_payment_amount(order: Order) -> float:
    if getattr(order, "total_price", None) is not None:
        return _json_float(order.total_price)
    return _json_float(order.amount)


def _save_audit(action: str, meta: dict):
    try:
        db.session.add(
            AuditLog(
                actor_user_id=None,
                action=action,
                target_type="payment",
                target_id=None,
                meta=json.dumps(meta),
            )
        )
        db.session.commit()
    except Exception:
        db.session.rollback()


def _extract_order_id(meta_raw) -> int | None:
    if not meta_raw:
        return None
    try:
        payload = json.loads(meta_raw) if isinstance(meta_raw, str) else dict(meta_raw)
    except Exception:
        return None
    oid = payload.get("order_id")
    try:
        return int(oid) if oid is not None else None
    except Exception:
        return None


def _ensure_payment_intent(*, user_id: int, provider: str, reference: str, purpose: str, amount: float, meta: dict) -> PaymentIntent:
    pi = PaymentIntent.query.filter_by(reference=reference).first()
    if not pi:
        pi = PaymentIntent(
            user_id=user_id,
            provider=provider,
            reference=reference,
            purpose=purpose,
            amount=amount,
            status="initialized",
            meta=json.dumps(meta),
        )
    else:
        pi.user_id = user_id
        pi.provider = provider
        pi.purpose = purpose
        pi.amount = amount
        pi.meta = json.dumps(meta)
        if (pi.status or "").strip().lower() == "failed":
            pi.status = "initialized"
    db.session.add(pi)
    db.session.commit()
    return pi


def _credit_wallet_from_reference(reference: str):
    pi = PaymentIntent.query.filter_by(reference=reference).first()
    if not pi:
        return False
    already_paid = (pi.status or "").strip().lower() == "paid"
    if already_paid:
        return True

    pi.status = "paid"
    pi.paid_at = datetime.utcnow()
    db.session.add(pi)
    db.session.commit()

    post_txn(int(pi.user_id), float(pi.amount or 0.0), kind="topup", direction="credit", reference=f"pay:{reference}")
    return True


def _mark_order_paid(order: Order, reference: str):
    if _order_is_paid(order):
        return
    try:
        from app.segments.segment_orders_api import _mark_paid
        _mark_paid(order, reference=reference, actor_id=None)
    except Exception:
        order.status = "paid"
        order.payment_reference = reference
    db.session.add(order)
    db.session.commit()


def _check_webhook_amount(pi: PaymentIntent | None, data: dict) -> bool:
    if not pi:
        return False
    amount_raw = data.get("amount")
    if amount_raw is None:
        return True
    try:
        amount = Decimal(str(amount_raw)) / Decimal("100")
    except Exception:
        return False
    expected = _json_decimal(pi.amount)
    return amount.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP) == expected


def process_paystack_webhook(*, payload: dict, raw: bytes, signature: str | None, source: str = "payments") -> tuple[dict, int]:
    settings = get_settings()
    mode = (getattr(settings, "integrations_mode", "disabled") or "disabled").strip().lower()
    strict = mode == "live" or (os.getenv("PAYSTACK_WEBHOOK_STRICT", "0").strip() == "1")

    verified = verify_signature(raw, signature) if signature else False
    if strict and not verified:
        return {"ok": False, "error": "INVALID_SIGNATURE"}, 401

    event = (payload.get("event") or "").strip()
    data = payload.get("data") or {}
    reference = (data.get("reference") or "").strip()

    event_id = ""
    try:
        event_id = (payload.get("id") or payload.get("event_id") or "").strip()
    except Exception:
        event_id = ""
    if not event_id:
        base = f"{event}:{reference}:{data.get('amount', '')}:{source}"
        event_id = hashlib.sha256(base.encode("utf-8")).hexdigest()[:32]

    existing = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
    if existing:
        return {"ok": True, "replayed": True, "verified": verified}, 200

    try:
        db.session.add(WebhookEvent(provider="paystack", event_id=event_id, reference=reference))
        db.session.commit()
    except Exception:
        db.session.rollback()

    _save_audit("paystack_webhook", {"verified": verified, "event": event, "reference": reference, "source": source})

    if event != "charge.success" or not reference:
        return {"ok": True, "verified": verified}, 200

    pi = PaymentIntent.query.filter_by(reference=reference).first()
    if not pi:
        return {"ok": True, "verified": verified, "ignored": True}, 200

    if not _check_webhook_amount(pi, data):
        return {"ok": False, "error": "AMOUNT_MISMATCH", "reference": reference}, 200

    if (pi.purpose or "").strip().lower() == "order":
        order_id = _extract_order_id(pi.meta)
        if not order_id:
            return {"ok": False, "error": "ORDER_ID_MISSING", "reference": reference}, 200
        order = db.session.get(Order, int(order_id))
        if not order:
            return {"ok": False, "error": "ORDER_NOT_FOUND", "reference": reference}, 200
        if _order_is_paid(order):
            pi.status = "paid"
            if not pi.paid_at:
                pi.paid_at = datetime.utcnow()
                db.session.add(pi)
                db.session.commit()
            return {"ok": True, "verified": verified, "already_paid": True}, 200

        pi.status = "paid"
        pi.paid_at = datetime.utcnow()
        db.session.add(pi)
        db.session.commit()
        _mark_order_paid(order, reference=reference)
        return {"ok": True, "verified": verified, "purpose": "order"}, 200

    _credit_wallet_from_reference(reference)
    return {"ok": True, "verified": verified, "purpose": "topup"}, 200


@payments_bp.post("/initialize")
def initialize_payment():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    data = request.get_json(silent=True) or {}
    idem = lookup_response(int(u.id), "/api/payments/initialize", data)
    if idem and idem[0] == "hit":
        return jsonify(idem[1]), idem[2]
    if idem and idem[0] == "conflict":
        return jsonify(idem[1]), idem[2]
    idem_row = idem[1] if idem and idem[0] == "miss" else None

    purpose = (data.get("purpose") or "topup").strip().lower()
    if purpose not in ("topup", "order"):
        return jsonify({"ok": False, "message": "purpose must be topup|order"}), 400

    settings = get_settings()
    try:
        provider = build_payments_provider(settings)
    except IntegrationDisabledError as e:
        return jsonify({"ok": False, "error": "INTEGRATION_DISABLED", "message": str(e)}), 503
    except IntegrationMisconfiguredError as e:
        return jsonify({"ok": False, "error": "INTEGRATION_MISCONFIGURED", "message": str(e)}), 500

    order = None
    order_id = None
    amount = Decimal("0.00")
    if purpose == "order":
        try:
            order_id = int(data.get("order_id"))
        except Exception:
            return jsonify({"ok": False, "message": "order_id required for order payments"}), 400
        order = db.session.get(Order, int(order_id))
        if not order:
            return jsonify({"ok": False, "message": "order not found"}), 404
        if not _is_admin(u) and int(order.buyer_id) != int(u.id):
            return jsonify({"ok": False, "message": "Forbidden"}), 403
        if _order_is_paid(order):
            return jsonify({"ok": False, "message": "order already paid"}), 409
        amount = _json_decimal(_order_payment_amount(order))
    else:
        try:
            amount = _json_decimal(data.get("amount") or 0)
        except Exception:
            amount = Decimal("0.00")
        if amount <= Decimal("0.00"):
            return jsonify({"ok": False, "message": "amount must be > 0"}), 400

    now_stamp = int(datetime.utcnow().timestamp())
    if purpose == "order":
        reference = (getattr(order, "payment_reference", None) or "").strip()
        if not reference:
            reference = f"FT-ORD-{int(order.id)}-{now_stamp}"
    else:
        reference = f"FT-TOP-{int(u.id)}-{now_stamp}"

    meta = {
        "purpose": purpose,
        "order_id": int(order.id) if order is not None else None,
        "initiated_by": int(u.id),
        "source": "api.payments.initialize",
    }

    try:
        pi = _ensure_payment_intent(
            user_id=int(u.id),
            provider=provider.name,
            reference=reference,
            purpose=purpose,
            amount=float(amount),
            meta=meta,
        )
        if order is not None:
            order.payment_reference = pi.reference
            db.session.add(order)
            db.session.commit()

        init = provider.initialize(
            order_id=int(order.id) if order is not None else None,
            amount=float(amount),
            email=u.email or "",
            reference=pi.reference,
            metadata=meta,
        )
        if init.reference and init.reference != pi.reference:
            pi.reference = init.reference
            db.session.add(pi)
            if order is not None:
                order.payment_reference = init.reference
                db.session.add(order)
            db.session.commit()

        response = {
            "ok": True,
            "provider": provider.name,
            "reference": init.reference,
            "authorization_url": init.authorization_url,
            "purpose": purpose,
            "order_id": int(order.id) if order is not None else None,
            "amount": float(amount),
        }
        if idem_row is not None:
            store_response(idem_row, response, 200)
        return jsonify(response), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("payments_initialize_failed")
        return jsonify({"ok": False, "error": "PAYMENT_INIT_FAILED", "message": str(e)}), 500


@payments_bp.get("/status")
def payment_status():
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401
    try:
        order_id = int(request.args.get("order_id"))
    except Exception:
        return jsonify({"ok": False, "message": "order_id required"}), 400

    order = db.session.get(Order, int(order_id))
    if not order:
        return jsonify({"ok": False, "error": "ORDER_NOT_FOUND"}), 404

    is_participant = (
        int(order.buyer_id) == int(u.id)
        or int(order.merchant_id) == int(u.id)
        or (order.driver_id is not None and int(order.driver_id) == int(u.id))
        or (order.inspector_id is not None and int(order.inspector_id) == int(u.id))
    )
    if not is_participant and not _is_admin(u):
        return jsonify({"ok": False, "message": "Forbidden"}), 403

    ref = (order.payment_reference or "").strip()
    pi = PaymentIntent.query.filter_by(reference=ref).first() if ref else None
    if not pi:
        rows = PaymentIntent.query.filter_by(purpose="order").order_by(PaymentIntent.created_at.desc()).limit(120).all()
        for row in rows:
            if _extract_order_id(row.meta) == int(order.id):
                pi = row
                break

    payment_status = (pi.status if pi else "unknown") or "unknown"
    return jsonify(
        {
            "ok": True,
            "order_id": int(order.id),
            "payment_reference": ref,
            "payment_status": payment_status,
            "order_status": (order.status or "").strip().lower(),
        }
    ), 200


@payments_bp.post("/webhook/paystack")
def paystack_webhook():
    raw = request.get_data() or b""
    sig = request.headers.get("X-Paystack-Signature")
    payload = request.get_json(silent=True) or {}
    body, status = process_paystack_webhook(payload=payload, raw=raw, signature=sig, source="api/payments/webhook/paystack")
    return jsonify(body), int(status)

