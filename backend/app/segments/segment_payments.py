from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP

from flask import Blueprint, jsonify, request, current_app, g

from app.extensions import db
from app.models import AuditLog, User, PaymentIntent, PaymentIntentTransition, WebhookEvent, Order, ShortletBooking
from app.utils.jwt_utils import decode_token
from app.utils.paystack_client import verify_signature
from app.utils.wallets import post_txn
from app.utils.autopilot import get_settings
from app.utils.feature_flags import is_enabled
from app.utils.rate_limit import check_limit
from app.utils.idempotency import lookup_response, store_response
from app.integrations.common import IntegrationDisabledError, IntegrationMisconfiguredError
from app.integrations.payments.factory import build_payments_provider
from app.integrations.payments.mock_provider import MockPaymentsProvider
from app.services.payment_intent_service import (
    PaymentIntentStatus,
    transition_intent,
)
from app.services.risk_engine_service import record_event
from app.services.referral_service import maybe_complete_referral_on_success

payments_bp = Blueprint("payments_bp", __name__, url_prefix="/api/payments")
admin_payments_bp = Blueprint("admin_payments_bp", __name__, url_prefix="/api/admin/payments")
public_payments_bp = Blueprint("public_payments_bp", __name__, url_prefix="/api/public")
admin_payment_intents_bp = Blueprint("admin_payment_intents_bp", __name__, url_prefix="/api/admin/payment-intents")
payment_intents_bp = Blueprint("payment_intents_bp", __name__, url_prefix="/api/payment-intents")

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


def _payments_mode(settings) -> str:
    mode = (getattr(settings, "payments_mode", None) or "").strip().lower()
    if mode in ("paystack_auto", "manual_company_account", "mock"):
        return mode
    provider = (getattr(settings, "payments_provider", "mock") or "mock").strip().lower()
    return "mock" if provider == "mock" else "paystack_auto"


def _coerce_manual_sla(raw_value, default_value: int = 360) -> int:
    try:
        raw = int(raw_value)
    except Exception:
        raw = int(default_value)
    if raw < 5:
        return 5
    if raw > 10080:
        return 10080
    return raw


def _manual_sla_minutes(settings) -> int:
    return _coerce_manual_sla(getattr(settings, "manual_payment_sla_minutes", 360), 360)


def _request_id() -> str:
    try:
        rid = getattr(g, "request_id", None)
        if rid:
            return str(rid)
    except Exception:
        pass
    return (request.headers.get("X-Request-Id") or "").strip()


def _rate_limit_or_none(action: str, *, limit: int, window_seconds: int, user_id: int | None = None):
    try:
        settings = get_settings()
        enabled = bool(getattr(settings, "rate_limit_enabled", True))
    except Exception:
        enabled = True
    if not enabled:
        return None
    ip = (request.headers.get("X-Forwarded-For") or request.remote_addr or "unknown").split(",")[0].strip()
    key = f"{action}:ip:{ip}"
    if user_id is not None:
        key = f"{key}:u:{int(user_id)}"
    ok, retry_after = check_limit(key, limit=limit, window_seconds=window_seconds)
    if ok:
        return None
    try:
        record_event(
            action,
            user=None,
            context={"rate_limited": True, "reason_code": "RATE_LIMIT_EXCEEDED", "retry_after": retry_after},
            request_id=_request_id(),
        )
    except Exception:
        db.session.rollback()
    return jsonify({"ok": False, "error": "RATE_LIMITED", "message": "Too many requests. Please retry later.", "retry_after": retry_after}), 429


def _manual_instructions_payload(settings=None) -> dict:
    s = settings or get_settings()
    bank_name = (getattr(s, "manual_payment_bank_name", None) or "").strip()
    account_number = (getattr(s, "manual_payment_account_number", None) or "").strip()
    account_name = (getattr(s, "manual_payment_account_name", None) or "").strip()
    note = (getattr(s, "manual_payment_note", None) or "").strip()
    if not bank_name:
        bank_name = (os.getenv("COMPANY_BANK_NAME") or "").strip()
    if not account_number:
        account_number = (os.getenv("COMPANY_ACCOUNT_NUMBER") or "").strip()
    if not account_name:
        account_name = (os.getenv("COMPANY_ACCOUNT_NAME") or "").strip()
    sla_minutes = _manual_sla_minutes(s)
    return {
        "mode": "manual_company_account",
        "message": "Manual payment is enabled. Complete bank transfer and keep your reference while awaiting admin confirmation.",
        "account_name": account_name,
        "account_number": account_number,
        "bank_name": bank_name,
        "note": note,
        "sla_minutes": int(sla_minutes),
        "supports_proof_submission": True,
    }


def _meta_dict(meta_raw) -> dict:
    if not meta_raw:
        return {}
    if isinstance(meta_raw, dict):
        return dict(meta_raw)
    try:
        parsed = json.loads(meta_raw)
        return parsed if isinstance(parsed, dict) else {}
    except Exception:
        return {}


def _meta_json(payload: dict) -> str:
    try:
        return json.dumps(payload or {})
    except Exception:
        return "{}"


def _manual_proof_payload(meta_raw) -> dict:
    parsed = _meta_dict(meta_raw)
    proof = parsed.get("manual_proof")
    if not isinstance(proof, dict):
        return {
            "submitted": False,
            "bank_txn_reference": "",
            "note": "",
            "submitted_at": None,
            "submitted_by_user_id": None,
        }
    return {
        "submitted": bool((proof.get("bank_txn_reference") or "").strip() or (proof.get("note") or "").strip()),
        "bank_txn_reference": str(proof.get("bank_txn_reference") or ""),
        "note": str(proof.get("note") or ""),
        "submitted_at": proof.get("submitted_at"),
        "submitted_by_user_id": proof.get("submitted_by_user_id"),
    }


def _find_manual_intent_for_order(order_id: int) -> PaymentIntent | None:
    rows = (
        PaymentIntent.query
        .filter_by(provider="manual_company_account", purpose="order")
        .order_by(PaymentIntent.created_at.desc())
        .limit(300)
        .all()
    )
    for row in rows:
        if _extract_order_id(row.meta) == int(order_id):
            return row
    return None


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


def _save_admin_audit(*, actor_id: int | None, action: str, target_type: str, target_id: int | None, meta: dict):
    try:
        db.session.add(
            AuditLog(
                actor_user_id=actor_id,
                action=action[:64],
                target_type=target_type[:64],
                target_id=target_id,
                meta=_meta_json(meta)[:3000],
            )
        )
        db.session.commit()
    except Exception:
        db.session.rollback()


def _payments_mode_payload(settings) -> dict:
    mode = _payments_mode(settings)
    return {
        "mode": mode,
        "manual_payment_bank_name": (getattr(settings, "manual_payment_bank_name", "") or "").strip(),
        "manual_payment_account_number": (getattr(settings, "manual_payment_account_number", "") or "").strip(),
        "manual_payment_account_name": (getattr(settings, "manual_payment_account_name", "") or "").strip(),
        "manual_payment_note": (getattr(settings, "manual_payment_note", "") or "").strip(),
        "manual_payment_sla_minutes": _manual_sla_minutes(settings),
        "instructions": _manual_instructions_payload(settings),
    }


def _paystack_is_available(settings) -> bool:
    if not is_enabled("payments.paystack_enabled", default=bool(getattr(settings, "paystack_enabled", False)), settings=settings):
        return False
    mode = _payments_mode(settings)
    if mode == "mock":
        return True
    provider = (getattr(settings, "payments_provider", "mock") or "mock").strip().lower()
    enabled = bool(getattr(settings, "paystack_enabled", False))
    if mode != "paystack_auto":
        return False
    if provider == "mock":
        return False
    return bool(enabled)


def _payment_methods_payload(*, settings, scope: str) -> dict:
    paystack_available = _paystack_is_available(settings)
    mode = _payments_mode(settings)
    methods = {
        "wallet": {
            "id": "wallet",
            "available": True,
            "reason": "Wallet checkout is always available.",
        },
        "paystack_card": {
            "id": "paystack_card",
            "available": bool(paystack_available),
            "reason": "Paystack card checkout is available."
            if paystack_available
            else "Paystack is unavailable in current runtime mode.",
        },
        "paystack_transfer": {
            "id": "paystack_transfer",
            "available": bool(paystack_available),
            "reason": "Paystack transfer checkout is available."
            if paystack_available
            else "Paystack is unavailable in current runtime mode.",
        },
        "bank_transfer_manual": {
            "id": "bank_transfer_manual",
            "available": not bool(paystack_available),
            "reason": "Manual transfer is enabled because Paystack is unavailable."
            if not paystack_available
            else "Manual transfer is hidden while Paystack auto mode is available.",
        },
    }
    return {
        "ok": True,
        "scope": scope,
        "mode": mode,
        "paystack_available": bool(paystack_available),
        "methods": methods,
    }


def _extract_order_id(meta_raw) -> int | None:
    payload = _meta_dict(meta_raw)
    oid = payload.get("order_id")
    if oid is None:
        order_ids = payload.get("order_ids")
        if isinstance(order_ids, list) and order_ids:
            oid = order_ids[0]
    try:
        return int(oid) if oid is not None else None
    except Exception:
        return None


def _extract_order_ids(meta_raw) -> list[int]:
    payload = _meta_dict(meta_raw)
    out: list[int] = []
    order_ids = payload.get("order_ids")
    if isinstance(order_ids, list):
        for value in order_ids:
            try:
                out.append(int(value))
            except Exception:
                continue
    oid = payload.get("order_id")
    if oid is not None:
        try:
            parsed = int(oid)
            if parsed not in out:
                out.append(parsed)
        except Exception:
            pass
    return out


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
            updated_at=datetime.utcnow(),
            meta=json.dumps(meta),
        )
    else:
        pi.user_id = user_id
        pi.provider = provider
        pi.purpose = purpose
        pi.amount = amount
        pi.meta = json.dumps(meta)
        pi.updated_at = datetime.utcnow()
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

    transition_intent(
        pi,
        PaymentIntentStatus.PAID,
        actor={"type": "system"},
        idempotency_key=f"wallet_topup:{reference}",
        reason="topup_verified",
        metadata={"reference": reference},
    )

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
    try:
        maybe_complete_referral_on_success(
            referred_user_id=int(order.buyer_id),
            source_type="order",
            source_id=int(order.id),
        )
    except Exception:
        db.session.rollback()


def _mark_shortlet_booking_paid(booking: ShortletBooking, reference: str):
    booking.payment_status = "paid"
    booking.status = "confirmed"
    db.session.add(booking)
    db.session.commit()
    try:
        maybe_complete_referral_on_success(
            referred_user_id=int(booking.user_id) if booking.user_id is not None else None,
            source_type="shortlet_booking",
            source_id=int(booking.id),
        )
    except Exception:
        db.session.rollback()


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


def _touch_last_paystack_webhook(settings) -> None:
    try:
        settings.last_paystack_webhook_at = datetime.utcnow()
        db.session.add(settings)
        db.session.commit()
    except Exception:
        db.session.rollback()


def process_paystack_webhook(*, payload: dict, raw: bytes, signature: str | None, source: str = "payments") -> tuple[dict, int]:
    webhook_row = None
    try:
        settings = get_settings()
        mode = (getattr(settings, "integrations_mode", "disabled") or "disabled").strip().lower()
        provider = (getattr(settings, "payments_provider", "mock") or "mock").strip().lower()
        enabled = bool(getattr(settings, "paystack_enabled", False))

        if not isinstance(payload, dict):
            return {"ok": False, "error": "INVALID_PAYLOAD", "message": "payload must be an object"}, 400

        event_raw = payload.get("event")
        data_raw = payload.get("data")
        if not isinstance(event_raw, str) or not event_raw.strip():
            return {"ok": False, "error": "INVALID_PAYLOAD", "message": "event is required"}, 400
        if data_raw is None:
            data = {}
        elif isinstance(data_raw, dict):
            data = data_raw
        else:
            return {"ok": False, "error": "INVALID_PAYLOAD", "message": "data must be an object"}, 400

        event = event_raw.strip()
        reference = str((data.get("reference") or "")).strip()
        _touch_last_paystack_webhook(settings)
        payload_hash = hashlib.sha256(raw or b"").hexdigest()
        request_id = _request_id() or None

        # Live Paystack must validate signature. Mock/disabled paths never require it.
        verified = False
        strict_signature = mode == "live" and provider == "paystack" and enabled and not str(source or "").startswith("admin_replay")
        if strict_signature:
            secret = (os.getenv("PAYSTACK_WEBHOOK_SECRET") or os.getenv("PAYSTACK_SECRET_KEY") or "").strip()
            if not secret:
                return {
                    "ok": False,
                    "error": "INTEGRATION_MISCONFIGURED",
                    "message": "missing PAYSTACK_WEBHOOK_SECRET (or PAYSTACK_SECRET_KEY)",
                }, 400
            if not signature:
                return {
                    "ok": False,
                    "error": "INTEGRATION_MISCONFIGURED",
                    "message": "missing X-Paystack-Signature",
                }, 400
            verified = bool(verify_signature(raw or b"", signature))
            if not verified:
                return {"ok": False, "error": "INVALID_SIGNATURE"}, 400

        event_id = ""
        try:
            maybe_id = payload.get("id") or payload.get("event_id") or ""
            event_id = str(maybe_id).strip()
        except Exception:
            event_id = ""
        if not event_id:
            base = f"{event}:{reference}:{data.get('amount', '')}:{source}"
            event_id = hashlib.sha256(base.encode("utf-8")).hexdigest()[:32]

        existing = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
        if existing:
            if (existing.status or "").strip().lower() in ("processed", "ignored", "replayed"):
                return {"ok": True, "replayed": True, "verified": verified}, 200
            return {"ok": True, "replayed": True, "verified": verified}, 200

        try:
            webhook_row = WebhookEvent(
                provider="paystack",
                event_id=event_id,
                reference=reference,
                status="received",
                request_id=request_id,
                payload_hash=payload_hash,
                payload_json=((raw or b"{}").decode("utf-8", errors="ignore"))[:200000],
                processed_at=None,
                error=None,
            )
            db.session.add(webhook_row)
            db.session.commit()
        except Exception:
            db.session.rollback()

        _save_audit("paystack_webhook", {"verified": verified, "event": event, "reference": reference, "source": source})

        if event != "charge.success":
            try:
                if webhook_row is None:
                    webhook_row = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
                if webhook_row:
                    webhook_row.status = "ignored"
                    webhook_row.processed_at = datetime.utcnow()
                    webhook_row.error = None
                    db.session.add(webhook_row)
                    db.session.commit()
            except Exception:
                db.session.rollback()
            return {"ok": True, "verified": verified}, 200
        if not reference:
            try:
                if webhook_row is None:
                    webhook_row = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
                if webhook_row:
                    webhook_row.status = "invalid_payload"
                    webhook_row.processed_at = datetime.utcnow()
                    webhook_row.error = "data.reference_missing"
                    db.session.add(webhook_row)
                    db.session.commit()
            except Exception:
                db.session.rollback()
            return {"ok": False, "error": "INVALID_PAYLOAD", "message": "data.reference is required"}, 400

        pi = PaymentIntent.query.filter_by(reference=reference).first()
        if not pi:
            try:
                if webhook_row is None:
                    webhook_row = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
                if webhook_row:
                    webhook_row.status = "intent_not_found"
                    webhook_row.processed_at = datetime.utcnow()
                    webhook_row.error = "INTENT_NOT_FOUND"
                    db.session.add(webhook_row)
                    db.session.commit()
            except Exception:
                db.session.rollback()
            return {"ok": True, "verified": verified, "ignored": True}, 200

        if not _check_webhook_amount(pi, data):
            try:
                if webhook_row is None:
                    webhook_row = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
                if webhook_row:
                    webhook_row.status = "amount_mismatch"
                    webhook_row.processed_at = datetime.utcnow()
                    webhook_row.error = "AMOUNT_MISMATCH"
                    db.session.add(webhook_row)
                    db.session.commit()
            except Exception:
                db.session.rollback()
            try:
                record_event(
                    "webhook_success",
                    user=None,
                    context={"amount_mismatch": True, "reference": reference, "event_id": event_id},
                    request_id=request_id,
                )
            except Exception:
                db.session.rollback()
            return {"ok": False, "error": "AMOUNT_MISMATCH", "reference": reference}, 200

        purpose_key = (pi.purpose or "").strip().lower()
        if purpose_key == "shortlet_booking":
            payload_meta = _meta_dict(pi.meta)
            try:
                booking_id = int(payload_meta.get("booking_id"))
            except Exception:
                booking_id = None
            booking = db.session.get(ShortletBooking, int(booking_id)) if booking_id else None
            if not booking:
                try:
                    if webhook_row is None:
                        webhook_row = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
                    if webhook_row:
                        webhook_row.status = "booking_not_found"
                        webhook_row.processed_at = datetime.utcnow()
                        webhook_row.error = "BOOKING_NOT_FOUND"
                        db.session.add(webhook_row)
                        db.session.commit()
                except Exception:
                    db.session.rollback()
                return {"ok": False, "error": "BOOKING_NOT_FOUND", "reference": reference}, 200

            if (booking.payment_status or "").strip().lower() == "paid":
                try:
                    transition_intent(
                        pi,
                        PaymentIntentStatus.PAID,
                        actor={"type": "webhook"},
                        idempotency_key=f"webhook:paystack:{event_id}",
                        reason="charge_success_replay",
                        metadata={"reference": reference, "source": source},
                    )
                except Exception:
                    db.session.rollback()
                try:
                    if webhook_row is None:
                        webhook_row = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
                    if webhook_row:
                        webhook_row.status = "processed"
                        webhook_row.processed_at = datetime.utcnow()
                        webhook_row.error = None
                        db.session.add(webhook_row)
                        db.session.commit()
                except Exception:
                    db.session.rollback()
                return {"ok": True, "verified": verified, "already_paid": True, "booking_id": int(booking.id)}, 200

            transition_intent(
                pi,
                PaymentIntentStatus.PAID,
                actor={"type": "webhook"},
                idempotency_key=f"webhook:paystack:{event_id}",
                reason="charge_success_shortlet_booking",
                metadata={"reference": reference, "source": source, "booking_id": int(booking.id)},
            )
            _mark_shortlet_booking_paid(booking, reference=reference)
            try:
                if webhook_row is None:
                    webhook_row = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
                if webhook_row:
                    webhook_row.status = "processed"
                    webhook_row.processed_at = datetime.utcnow()
                    webhook_row.error = None
                    db.session.add(webhook_row)
                    db.session.commit()
            except Exception:
                db.session.rollback()
            return {"ok": True, "verified": verified, "purpose": "shortlet_booking", "booking_id": int(booking.id)}, 200

        if purpose_key == "order":
            order_ids = _extract_order_ids(pi.meta)
            if not order_ids:
                try:
                    if webhook_row is None:
                        webhook_row = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
                    if webhook_row:
                        webhook_row.status = "order_missing"
                        webhook_row.processed_at = datetime.utcnow()
                        webhook_row.error = "ORDER_ID_MISSING"
                        db.session.add(webhook_row)
                        db.session.commit()
                except Exception:
                    db.session.rollback()
                return {"ok": False, "error": "ORDER_ID_MISSING", "reference": reference}, 200
            orders: list[Order] = []
            missing = []
            for oid in order_ids:
                row = db.session.get(Order, int(oid))
                if row is None:
                    missing.append(int(oid))
                else:
                    orders.append(row)
            if missing:
                try:
                    if webhook_row is None:
                        webhook_row = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
                    if webhook_row:
                        webhook_row.status = "order_not_found"
                        webhook_row.processed_at = datetime.utcnow()
                        webhook_row.error = "ORDER_NOT_FOUND"
                        db.session.add(webhook_row)
                        db.session.commit()
                except Exception:
                    db.session.rollback()
                return {"ok": False, "error": "ORDER_NOT_FOUND", "reference": reference, "missing_order_ids": missing}, 200
            if orders and all(_order_is_paid(order) for order in orders):
                try:
                    transition_intent(
                        pi,
                        PaymentIntentStatus.PAID,
                        actor={"type": "webhook"},
                        idempotency_key=f"webhook:paystack:{event_id}",
                        reason="charge_success_replay",
                        metadata={"reference": reference, "source": source},
                    )
                except Exception:
                    db.session.rollback()
                try:
                    if webhook_row is None:
                        webhook_row = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
                    if webhook_row:
                        webhook_row.status = "processed"
                        webhook_row.processed_at = datetime.utcnow()
                        webhook_row.error = None
                        db.session.add(webhook_row)
                        db.session.commit()
                except Exception:
                    db.session.rollback()
                return {"ok": True, "verified": verified, "already_paid": True, "order_ids": [int(o.id) for o in orders]}, 200

            transition_intent(
                pi,
                PaymentIntentStatus.PAID,
                actor={"type": "webhook"},
                idempotency_key=f"webhook:paystack:{event_id}",
                reason="charge_success",
                metadata={"reference": reference, "source": source},
            )
            paid_ids = []
            for order in orders:
                if _order_is_paid(order):
                    continue
                _mark_order_paid(order, reference=reference)
                paid_ids.append(int(order.id))
            try:
                if webhook_row is None:
                    webhook_row = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
                if webhook_row:
                    webhook_row.status = "processed"
                    webhook_row.processed_at = datetime.utcnow()
                    webhook_row.error = None
                    db.session.add(webhook_row)
                    db.session.commit()
            except Exception:
                db.session.rollback()
            try:
                record_event(
                    "webhook_success",
                    user=None,
                    context={"reference": reference, "event_id": event_id, "order_ids": [int(o.id) for o in orders]},
                    request_id=request_id,
                )
            except Exception:
                db.session.rollback()
            return {"ok": True, "verified": verified, "purpose": "order", "order_ids": [int(o.id) for o in orders], "paid_ids": paid_ids}, 200

        _credit_wallet_from_reference(reference)
        try:
            if webhook_row is None:
                webhook_row = WebhookEvent.query.filter_by(provider="paystack", event_id=event_id).first()
            if webhook_row:
                webhook_row.status = "processed"
                webhook_row.processed_at = datetime.utcnow()
                webhook_row.error = None
                db.session.add(webhook_row)
                db.session.commit()
        except Exception:
            db.session.rollback()
        return {"ok": True, "verified": verified, "purpose": "topup"}, 200
    except Exception as e:
        try:
            db.session.rollback()
        except Exception:
            pass
        try:
            if webhook_row is not None:
                webhook_row.status = "failed"
                webhook_row.error = f"{type(e).__name__}: {e}"
                webhook_row.processed_at = datetime.utcnow()
                db.session.add(webhook_row)
                db.session.commit()
        except Exception:
            db.session.rollback()
        current_app.logger.exception("paystack_webhook_processing_failed source=%s", source)
        return {
            "ok": False,
            "error": "WEBHOOK_PROCESSING_FAILED",
            "message": f"{type(e).__name__}",
        }, 200


@public_payments_bp.get("/manual-payment-instructions")
def public_manual_payment_instructions():
    settings = get_settings()
    mode = _payments_mode(settings)
    payload = _manual_instructions_payload(settings)
    return jsonify(
        {
            "ok": True,
            "mode": mode,
            "manual_enabled": mode == "manual_company_account",
            "instructions": payload,
        }
    ), 200


@payments_bp.get("/methods")
def payment_methods():
    settings = get_settings()
    scope = (request.args.get("scope") or "order").strip().lower()
    if scope not in ("order", "shortlet"):
        scope = "order"
    return jsonify(_payment_methods_payload(settings=settings, scope=scope)), 200


@admin_payments_bp.get("/mode")
def admin_get_payments_mode():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    settings = get_settings()
    return jsonify({"ok": True, "settings": _payments_mode_payload(settings)}), 200


@admin_payments_bp.post("/mode")
def admin_set_payments_mode():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    data = request.get_json(silent=True) or {}
    mode = str(data.get("mode") or "").strip().lower()
    if mode not in ("paystack_auto", "manual_company_account", "mock"):
        return jsonify({"ok": False, "message": "mode must be paystack_auto|manual_company_account|mock"}), 400

    settings = get_settings()
    old_mode = _payments_mode(settings)
    settings.payments_mode = mode
    settings.payments_mode_changed_at = datetime.utcnow()
    settings.payments_mode_changed_by = int(u.id)
    if mode == "mock":
        settings.payments_provider = "mock"
    elif mode == "paystack_auto" and (getattr(settings, "payments_provider", "mock") or "mock").strip().lower() == "mock":
        settings.payments_provider = "paystack"

    if "manual_payment_bank_name" in data:
        settings.manual_payment_bank_name = str(data.get("manual_payment_bank_name") or "").strip()[:120]
    if "manual_payment_account_number" in data:
        settings.manual_payment_account_number = str(data.get("manual_payment_account_number") or "").strip()[:64]
    if "manual_payment_account_name" in data:
        settings.manual_payment_account_name = str(data.get("manual_payment_account_name") or "").strip()[:120]
    if "manual_payment_note" in data:
        settings.manual_payment_note = str(data.get("manual_payment_note") or "").strip()[:240]
    if "manual_payment_sla_minutes" in data:
        settings.manual_payment_sla_minutes = _coerce_manual_sla(
            data.get("manual_payment_sla_minutes"),
            int(getattr(settings, "manual_payment_sla_minutes", 360) or 360),
        )

    db.session.add(settings)
    db.session.commit()

    if old_mode != mode:
        _save_admin_audit(
            actor_id=int(u.id),
            action="payments_mode_changed",
            target_type="autopilot_settings",
            target_id=int(getattr(settings, "id", 1) or 1),
            meta={"from": old_mode, "to": mode},
        )

    return jsonify({"ok": True, "settings": _payments_mode_payload(settings)}), 200


@payments_bp.post("/initialize")
def initialize_payment():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    rl = _rate_limit_or_none("payment_initialize", limit=40, window_seconds=300, user_id=int(u.id))
    if rl is not None:
        return rl

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
    payment_method_raw = (data.get("payment_method") or "").strip().lower()
    payment_method = payment_method_raw or "paystack_card"
    if payment_method == "paystack":
        payment_method = "paystack_card"
    if payment_method not in ("paystack_card", "paystack_transfer", "wallet", "bank_transfer_manual"):
        return jsonify(
            {
                "ok": False,
                "message": "payment_method must be wallet|paystack_card|paystack_transfer|bank_transfer_manual",
            }
        ), 400

    settings = get_settings()
    payments_mode = _payments_mode(settings)

    order = None
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
    meta = {
        "purpose": purpose,
        "payment_method": payment_method,
        "order_id": int(order.id) if order is not None else None,
        "initiated_by": int(u.id),
        "source": "api.payments.initialize",
    }
    try:
        record_event(
            "payment_initialize",
            user=u,
            context={
                "purpose": purpose,
                "order_id": int(order.id) if order is not None else None,
                "amount": float(amount),
            },
            request_id=_request_id(),
        )
    except Exception:
        db.session.rollback()

    if payment_method == "wallet":
        return jsonify(
            {
                "ok": False,
                "error": "UNSUPPORTED_PAYMENT_METHOD",
                "message": "Use wallet checkout from order/cart flows.",
            }
        ), 400

    if payment_method == "bank_transfer_manual" and _paystack_is_available(settings):
        return jsonify(
            {
                "ok": False,
                "error": "PAYMENT_METHOD_UNAVAILABLE",
                "message": "Manual transfer is currently unavailable while Paystack auto mode is active.",
            }
        ), 409

    if payment_method == "bank_transfer_manual" or payments_mode == "manual_company_account":
        if purpose != "order":
            return jsonify({"ok": False, "error": "INTEGRATION_DISABLED", "message": "manual payment mode supports order payments only"}), 503
        if order is None:
            return jsonify({"ok": False, "message": "order_id required for order payments"}), 400

        existing_manual = _find_manual_intent_for_order(int(order.id))
        reference = (getattr(order, "payment_reference", None) or "").strip()
        if existing_manual and not reference:
            reference = (existing_manual.reference or "").strip()
        if not reference:
            reference = f"FT-MAN-{int(order.id)}-{now_stamp}"

        try:
            manual_meta = {
                **meta,
                "mode": "manual_company_account",
                "buyer_display_name": (getattr(u, "name", None) or "").strip(),
                "buyer_email": (getattr(u, "email", None) or "").strip(),
                "buyer_phone": (getattr(u, "phone", None) or "").strip(),
            }
            pi = _ensure_payment_intent(
                user_id=int(u.id),
                provider="manual_company_account",
                reference=reference,
                purpose=purpose,
                amount=float(amount),
                meta=manual_meta,
            )
            transition_intent(
                pi,
                PaymentIntentStatus.MANUAL_PENDING,
                actor={"type": "user", "id": int(u.id)},
                idempotency_key=f"init:{pi.reference}:manual_pending",
                reason="manual_initialize",
                metadata={"order_id": int(order.id), "source": "initialize"},
            )
            order.payment_reference = pi.reference
            db.session.add(order)
            db.session.commit()
            response = {
                "ok": True,
                "mode": "manual_company_account",
                "provider": "manual_company_account",
                "payment_method": "bank_transfer_manual",
                "payment_intent_id": int(pi.id),
                "payment_status": pi.status or PaymentIntentStatus.MANUAL_PENDING,
                "reference": pi.reference,
                "authorization_url": None,
                "purpose": purpose,
                "order_id": int(order.id),
                "amount": float(amount),
                "requires_admin_mark_paid": True,
                "manual_instructions": _manual_instructions_payload(settings),
            }
            if idem_row is not None:
                store_response(idem_row, response, 200)
            return jsonify(response), 200
        except Exception as e:
            db.session.rollback()
            current_app.logger.exception("payments_initialize_manual_failed")
            return jsonify({"ok": False, "error": "PAYMENT_INIT_FAILED", "message": str(e)}), 500

    if payment_method in ("paystack_card", "paystack_transfer") and not _paystack_is_available(settings):
        return jsonify(
            {
                "ok": False,
                "error": "INTEGRATION_DISABLED",
                "message": "Paystack checkout is unavailable in current mode.",
            }
        ), 503

    if payments_mode == "mock":
        provider = MockPaymentsProvider()
    else:
        try:
            provider = build_payments_provider(settings)
        except IntegrationDisabledError as e:
            return jsonify({"ok": False, "error": "INTEGRATION_DISABLED", "message": str(e)}), 503
        except IntegrationMisconfiguredError as e:
            return jsonify({"ok": False, "error": "INTEGRATION_MISCONFIGURED", "message": str(e)}), 500

    if purpose == "order":
        reference = (getattr(order, "payment_reference", None) or "").strip()
        if not reference:
            reference = f"FT-ORD-{int(order.id)}-{now_stamp}"
    else:
        reference = f"FT-TOP-{int(u.id)}-{now_stamp}"

    try:
        pi = _ensure_payment_intent(
            user_id=int(u.id),
            provider=provider.name,
            reference=reference,
            purpose=purpose,
            amount=float(amount),
            meta=meta,
        )
        try:
            transition_intent(
                pi,
                PaymentIntentStatus.INITIALIZED,
                actor={"type": "user", "id": int(u.id)},
                idempotency_key=f"init:{pi.reference}:initialized",
                reason="payment_initialized",
                metadata={"purpose": purpose, "order_id": int(order.id) if order is not None else None},
            )
        except Exception:
            db.session.rollback()
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
            "mode": payments_mode,
            "payment_method": payment_method,
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
    proof = _manual_proof_payload(pi.meta if pi else None)
    return jsonify(
        {
            "ok": True,
            "order_id": int(order.id),
            "payment_reference": ref,
            "payment_intent_id": int(pi.id) if pi else None,
            "payment_status": payment_status,
            "payment_mode": (pi.provider if pi else None) or _payments_mode(get_settings()),
            "proof_submitted": bool(proof.get("submitted")),
            "proof_submitted_at": proof.get("submitted_at"),
            "order_status": (order.status or "").strip().lower(),
        }
    ), 200


@payments_bp.post("/manual/<int:intent_id>/proof")
def submit_manual_payment_proof(intent_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    pi = db.session.get(PaymentIntent, int(intent_id))
    if not pi or (pi.provider or "").strip().lower() != "manual_company_account":
        return jsonify({"ok": False, "error": "MANUAL_INTENT_NOT_FOUND"}), 404

    status = (pi.status or "").strip().lower()
    if status not in ("manual_pending", "initialized"):
        return jsonify({"ok": False, "error": "INTENT_NOT_PENDING", "status": status}), 409

    order_id = _extract_order_id(pi.meta)
    order = db.session.get(Order, int(order_id)) if order_id else None
    if not order:
        return jsonify({"ok": False, "error": "ORDER_NOT_FOUND"}), 404

    if int(order.buyer_id or 0) != int(u.id or 0) and not _is_admin(u):
        return jsonify({"ok": False, "error": "FORBIDDEN"}), 403

    data = request.get_json(silent=True) or {}
    bank_txn_reference = str(data.get("bank_txn_reference") or "").strip()
    note = str(data.get("note") or "").strip()
    if not bank_txn_reference and not note:
        return jsonify({"ok": False, "message": "bank_txn_reference or note is required"}), 400

    payload = _meta_dict(pi.meta)
    payload["manual_proof"] = {
        "bank_txn_reference": bank_txn_reference[:120],
        "note": note[:240],
        "submitted_at": datetime.utcnow().isoformat(),
        "submitted_by_user_id": int(u.id),
    }
    pi.meta = _meta_json(payload)
    pi.updated_at = datetime.utcnow()

    try:
        db.session.add(pi)
        db.session.commit()
        return jsonify(
            {
                "ok": True,
                "payment_intent_id": int(pi.id),
                "order_id": int(order.id),
                "proof_submitted": True,
            }
        ), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("manual_payment_proof_submit_failed intent_id=%s", int(intent_id))
        return jsonify({"ok": False, "error": "PROOF_SUBMIT_FAILED", "message": str(e)}), 500


@payments_bp.post("/payment-intents/<int:intent_id>/manual-proof")
def submit_manual_payment_proof_alias(intent_id: int):
    return submit_manual_payment_proof(intent_id)


@payment_intents_bp.post("/<int:intent_id>/manual-proof")
def submit_manual_payment_proof_root_alias(intent_id: int):
    return submit_manual_payment_proof(intent_id)


@payments_bp.post("/webhook/paystack")
def paystack_webhook():
    try:
        raw = request.get_data() or b""
        sig = request.headers.get("X-Paystack-Signature")
        payload = request.get_json(silent=True) or {}
        body, status = process_paystack_webhook(payload=payload, raw=raw, signature=sig, source="api/payments/webhook/paystack")
        return jsonify(body), int(status)
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        current_app.logger.exception("paystack_webhook_route_failed")
        return jsonify({"ok": False, "error": "WEBHOOK_HANDLER_FAILED"}), 200


def _parse_page_values() -> tuple[int, int]:
    try:
        limit = int(request.args.get("limit") or 50)
    except Exception:
        limit = 50
    try:
        offset = int(request.args.get("offset") or 0)
    except Exception:
        offset = 0
    if limit < 1:
        limit = 1
    if limit > 100:
        limit = 100
    if offset < 0:
        offset = 0
    return limit, offset


def _manual_pending_filter_query():
    return PaymentIntent.query.filter_by(provider="manual_company_account", purpose="order")


def _manual_queue_base_query(status_filter: str):
    query = _manual_pending_filter_query()
    status_key = (status_filter or "manual_pending").strip().lower()
    if status_key == "all":
        return query, status_key
    if status_key == "manual_pending":
        return query.filter(PaymentIntent.status.in_(("manual_pending", "initialized"))), status_key
    if status_key in ("paid", "cancelled", "failed"):
        return query.filter(PaymentIntent.status == status_key), status_key
    return None, status_key


def _manual_intent_context(row: PaymentIntent):
    oid = _extract_order_id(row.meta)
    order = db.session.get(Order, int(oid)) if oid else None
    buyer = None
    if order and order.buyer_id is not None:
        buyer = db.session.get(User, int(order.buyer_id))
    if buyer is None and row.user_id is not None:
        buyer = db.session.get(User, int(row.user_id))
    proof = _manual_proof_payload(row.meta)
    return oid, order, buyer, proof


def _manual_intent_item(row: PaymentIntent) -> dict:
    oid, order, buyer, proof = _manual_intent_context(row)
    payload = _meta_dict(row.meta)
    try:
        booking_id = int(payload.get("booking_id")) if payload.get("booking_id") is not None else None
    except Exception:
        booking_id = None
    return {
        "payment_intent_id": int(row.id),
        "intent_id": int(row.id),
        "reference": row.reference or "",
        "status": row.status or "",
        "amount": float(row.amount or 0.0),
        "order_id": int(oid) if oid else None,
        "booking_id": booking_id,
        "buyer_id": int(order.buyer_id) if order and order.buyer_id is not None else None,
        "buyer_email": getattr(buyer, "email", "") or "",
        "buyer_phone": getattr(buyer, "phone", "") or "",
        "buyer_name": getattr(buyer, "name", "") or "",
        "merchant_id": int(order.merchant_id) if order and order.merchant_id is not None else None,
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
        "proof_submitted": bool(proof.get("submitted")),
        "proof_submitted_at": proof.get("submitted_at"),
        "bank_txn_reference": proof.get("bank_txn_reference"),
    }


def _manual_intent_details_payload(row: PaymentIntent) -> dict:
    oid, order, buyer, proof = _manual_intent_context(row)
    payload = _meta_dict(row.meta)
    try:
        booking_id = int(payload.get("booking_id")) if payload.get("booking_id") is not None else None
    except Exception:
        booking_id = None
    booking = db.session.get(ShortletBooking, int(booking_id)) if booking_id else None
    transitions = (
        PaymentIntentTransition.query.filter_by(intent_id=int(row.id))
        .order_by(PaymentIntentTransition.created_at.asc())
        .all()
    )
    audits = (
        AuditLog.query.filter_by(target_type="payment_intent", target_id=int(row.id))
        .order_by(AuditLog.created_at.desc())
        .limit(30)
        .all()
    )
    return {
        "intent": _manual_intent_item(row),
        "order": {
            "id": int(order.id),
            "status": (order.status or "").strip().lower(),
            "payment_reference": order.payment_reference or "",
            "escrow_status": order.escrow_status or "NONE",
        }
        if order
        else None,
        "booking": {
            "id": int(booking.id),
            "shortlet_id": int(booking.shortlet_id),
            "status": (booking.status or "").strip().lower(),
            "payment_status": (booking.payment_status or "").strip().lower(),
        } if booking else None,
        "buyer": {
            "id": int(buyer.id),
            "name": (buyer.name or ""),
            "email": (buyer.email or ""),
            "phone": (buyer.phone or ""),
        }
        if buyer
        else None,
        "proof": proof,
        "transitions": [tr.to_dict() for tr in transitions],
        "audit": [row.to_dict() for row in audits],
    }


def _admin_manual_queue_impl(*, force_status: str | None = None):
    q = (request.args.get("q") or "").strip().lower()
    status_filter = (force_status or request.args.get("status") or "manual_pending").strip().lower()
    base_query, status_key = _manual_queue_base_query(status_filter)
    if base_query is None:
        return {"ok": False, "message": "status must be manual_pending|paid|cancelled|failed|all"}, 400

    try:
        min_amount = float(request.args.get("min_amount")) if request.args.get("min_amount") else None
    except Exception:
        return {"ok": False, "message": "min_amount invalid"}, 400
    try:
        max_amount = float(request.args.get("max_amount")) if request.args.get("max_amount") else None
    except Exception:
        return {"ok": False, "message": "max_amount invalid"}, 400

    limit, offset = _parse_page_values()
    rows = base_query.order_by(PaymentIntent.created_at.desc()).limit(500).all()

    items = []
    for row in rows:
        item = _manual_intent_item(row)
        amount_value = float(item.get("amount") or 0.0)
        if min_amount is not None and amount_value < min_amount:
            continue
        if max_amount is not None and amount_value > max_amount:
            continue

        searchable = " ".join(
            [
                str(item.get("reference") or ""),
                str(item.get("order_id") or ""),
                str(item.get("buyer_email") or ""),
                str(item.get("buyer_phone") or ""),
                str(item.get("buyer_name") or ""),
            ]
        ).lower()
        if q and q not in searchable:
            continue
        items.append(item)

    total = len(items)
    paged = items[offset : offset + limit]
    return {
        "ok": True,
        "status": status_key,
        "items": paged,
        "total": total,
        "limit": limit,
        "offset": offset,
    }, 200


@admin_payments_bp.get("/manual/queue")
def admin_manual_queue():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    body, code = _admin_manual_queue_impl(force_status=None)
    return jsonify(body), int(code)


@admin_payments_bp.get("/manual/pending")
def admin_manual_pending():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    body, code = _admin_manual_queue_impl(force_status="manual_pending")
    return jsonify(body), int(code)


@admin_payments_bp.get("/manual/<int:intent_id>")
def admin_manual_detail(intent_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    intent = db.session.get(PaymentIntent, int(intent_id))
    if not intent or (intent.provider or "").strip().lower() != "manual_company_account":
        return jsonify({"ok": False, "error": "MANUAL_INTENT_NOT_FOUND"}), 404
    return jsonify({"ok": True, **_manual_intent_details_payload(intent)}), 200


@admin_payments_bp.post("/manual/mark-paid")
def admin_mark_manual_paid():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    data = request.get_json(silent=True) or {}
    try:
        intent_id = int(data.get("payment_intent_id"))
    except Exception:
        return jsonify({"ok": False, "message": "payment_intent_id required"}), 400

    manual_intent = db.session.get(PaymentIntent, int(intent_id))
    if not manual_intent or (manual_intent.provider or "").strip().lower() != "manual_company_account":
        return jsonify({"ok": False, "error": "MANUAL_INTENT_NOT_FOUND"}), 404
    purpose = (manual_intent.purpose or "").strip().lower()
    if purpose not in ("order", "shortlet_booking"):
        return jsonify({"ok": False, "error": "INTENT_PURPOSE_UNSUPPORTED"}), 409

    booking = None
    orders: list[Order] = []
    if purpose == "shortlet_booking":
        payload_meta = _meta_dict(manual_intent.meta)
        try:
            booking_id = int(payload_meta.get("booking_id"))
        except Exception:
            booking_id = None
        booking = db.session.get(ShortletBooking, int(booking_id)) if booking_id else None
        if not booking:
            return jsonify({"ok": False, "error": "BOOKING_NOT_FOUND"}), 404
    else:
        order_ids = _extract_order_ids(manual_intent.meta)
        orders = [db.session.get(Order, int(oid)) for oid in order_ids]
        orders = [row for row in orders if row is not None]
        if not orders:
            return jsonify({"ok": False, "error": "ORDER_NOT_FOUND"}), 404

    current_status = (manual_intent.status or "").strip().lower()
    if current_status == PaymentIntentStatus.CANCELLED:
        return jsonify({"ok": False, "error": "INTENT_CANCELLED"}), 409
    if current_status == PaymentIntentStatus.FAILED:
        return jsonify({"ok": False, "error": "INTENT_FAILED"}), 409
    already_paid_orders = all(_order_is_paid(order) for order in orders) if orders else False
    already_paid_booking = bool(booking and (booking.payment_status or "").strip().lower() == "paid")
    if current_status == PaymentIntentStatus.PAID or already_paid_orders or already_paid_booking:
        return jsonify(
            {
                "ok": True,
                "idempotent": True,
                "payment_intent_id": int(manual_intent.id),
                "order_id": int(orders[0].id) if orders else None,
                "order_ids": [int(order.id) for order in orders],
                "booking_id": int(booking.id) if booking else None,
                "reference": manual_intent.reference or ((orders[0].payment_reference if orders else "") or ""),
            }
        ), 200

    amount_minor = data.get("amount_minor")
    if amount_minor is not None:
        try:
            expected_minor = int(sum(_order_payment_amount(order) for order in orders) * 100.0) if orders else int(booking.amount_minor or 0)
            provided_minor = int(amount_minor)
        except Exception:
            return jsonify({"ok": False, "message": "amount_minor invalid"}), 400
        if expected_minor != provided_minor:
            return jsonify({"ok": False, "error": "AMOUNT_MISMATCH", "expected_minor": expected_minor, "provided_minor": provided_minor}), 409

    bank_txn_reference = str((data.get("bank_txn_reference") or "")).strip()
    note = str((data.get("note") or "")).strip()
    now_stamp = int(datetime.utcnow().timestamp())
    final_reference = (manual_intent.reference or "").strip() or (orders[0].payment_reference if orders else "").strip()
    if not final_reference:
        anchor = int(orders[0].id) if orders else int(booking.id)
        final_reference = f"FT-MAN-{anchor}-{now_stamp}"

    try:
        manual_intent.reference = final_reference
        manual_intent.provider = "manual_company_account"
        manual_intent.purpose = "order"
        payload = _meta_dict(manual_intent.meta)
        payload["order_ids"] = [int(order.id) for order in orders]
        payload["order_id"] = int(orders[0].id) if orders else None
        payload["booking_id"] = int(booking.id) if booking else None
        payload["purpose"] = purpose
        payload["manual_mark_paid"] = {
            "marked_by_admin_id": int(u.id),
            "marked_at": datetime.utcnow().isoformat(),
            "bank_txn_reference": bank_txn_reference[:120],
            "note": note[:240],
            "source": "api.admin.payments.manual.mark-paid",
        }
        manual_intent.meta = _meta_json(payload)
        manual_intent.updated_at = datetime.utcnow()
        db.session.add(manual_intent)
        db.session.commit()

        transition_intent(
            manual_intent,
            PaymentIntentStatus.PAID,
            actor={"type": "admin", "id": int(u.id)},
            idempotency_key=f"admin:manual_mark_paid:{int(manual_intent.id)}",
            reason="manual_admin_mark_paid",
            metadata={
                "reference": final_reference,
                "order_ids": [int(order.id) for order in orders],
                "booking_id": int(booking.id) if booking else None,
                "bank_txn_reference": bank_txn_reference[:120],
            },
        )

        paid_ids = []
        if booking is not None:
            _mark_shortlet_booking_paid(booking, reference=final_reference)
            paid_ids.append(int(booking.id))
        else:
            for order in orders:
                if _order_is_paid(order):
                    continue
                _mark_order_paid(order, reference=final_reference)
                paid_ids.append(int(order.id))
        try:
            record_event(
                "manual_mark_paid",
                user=u,
                context={
                    "order_ids": [int(order.id) for order in orders],
                    "booking_id": int(booking.id) if booking else None,
                    "payment_intent_id": int(manual_intent.id),
                    "amount": float(sum(_order_payment_amount(order) for order in orders)) if orders else float(booking.total_amount if booking else 0.0),
                },
                request_id=_request_id(),
            )
        except Exception:
            db.session.rollback()
        _save_admin_audit(
            actor_id=int(u.id),
            action="manual_payment_mark_paid",
            target_type="payment_intent",
            target_id=int(manual_intent.id),
            meta={
                "order_ids": [int(order.id) for order in orders],
                "booking_id": int(booking.id) if booking else None,
                "reference": final_reference,
                "bank_txn_reference": bank_txn_reference[:120],
                "note": note[:240],
            },
        )
        return jsonify(
            {
                "ok": True,
                "payment_intent_id": int(manual_intent.id),
                "order_id": int(orders[0].id) if orders else None,
                "order_ids": [int(order.id) for order in orders],
                "booking_id": int(booking.id) if booking else None,
                "paid_ids": paid_ids,
                "reference": final_reference,
            }
        ), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("admin_mark_manual_paid_failed payment_intent_id=%s", int(manual_intent.id))
        return jsonify({"ok": False, "error": "MANUAL_MARK_PAID_FAILED", "message": str(e)}), 500


@admin_payments_bp.post("/payment-intents/<int:intent_id>/manual/mark-paid")
def admin_mark_manual_paid_alias(intent_id: int):
    payload = request.get_json(silent=True) or {}
    payload["payment_intent_id"] = int(intent_id)
    request._cached_json = (payload, payload)  # noqa: SLF001
    return admin_mark_manual_paid()


@admin_payments_bp.post("/manual/reject")
def admin_reject_manual_paid():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    data = request.get_json(silent=True) or {}
    try:
        intent_id = int(data.get("payment_intent_id"))
    except Exception:
        return jsonify({"ok": False, "message": "payment_intent_id required"}), 400

    intent = db.session.get(PaymentIntent, int(intent_id))
    if not intent or (intent.provider or "").strip().lower() != "manual_company_account":
        return jsonify({"ok": False, "error": "MANUAL_INTENT_NOT_FOUND"}), 404

    current_status = (intent.status or "").strip().lower()
    if current_status == PaymentIntentStatus.PAID:
        return jsonify({"ok": False, "error": "INTENT_ALREADY_PAID"}), 409
    if current_status == PaymentIntentStatus.CANCELLED:
        return jsonify({"ok": True, "idempotent": True, "payment_intent_id": int(intent.id), "status": "cancelled"}), 200
    if current_status == PaymentIntentStatus.FAILED:
        return jsonify({"ok": True, "idempotent": True, "payment_intent_id": int(intent.id), "status": "failed"}), 200

    reason = str(data.get("reason") or "").strip()
    if not reason:
        return jsonify({"ok": False, "message": "reason required"}), 400

    order_id = _extract_order_id(intent.meta)
    order_ids = _extract_order_ids(intent.meta)
    payload = _meta_dict(intent.meta)
    payload["manual_reject"] = {
        "reason": reason[:240],
        "rejected_by_admin_id": int(u.id),
        "rejected_at": datetime.utcnow().isoformat(),
    }
    intent.meta = _meta_json(payload)
    intent.updated_at = datetime.utcnow()
    db.session.add(intent)
    db.session.commit()

    transition_intent(
        intent,
        PaymentIntentStatus.CANCELLED,
        actor={"type": "admin", "id": int(u.id)},
        idempotency_key=f"admin:manual_reject:{int(intent.id)}",
        reason="manual_admin_reject",
        metadata={"order_id": int(order_id) if order_id else None, "reason": reason[:240]},
    )

    try:
        record_event(
            "manual_payment_reject",
            user=u,
            context={"payment_intent_id": int(intent.id), "order_id": int(order_id) if order_id else None, "order_ids": order_ids},
            request_id=_request_id(),
        )
    except Exception:
        db.session.rollback()

    _save_admin_audit(
        actor_id=int(u.id),
        action="manual_payment_reject",
        target_type="payment_intent",
        target_id=int(intent.id),
        meta={"order_id": int(order_id) if order_id else None, "order_ids": order_ids, "reason": reason[:240]},
    )

    return jsonify(
        {
            "ok": True,
            "payment_intent_id": int(intent.id),
            "order_id": int(order_id) if order_id else None,
            "order_ids": order_ids,
            "status": "cancelled",
        }
    ), 200


@admin_payments_bp.post("/payment-intents/<int:intent_id>/manual/reject")
def admin_reject_manual_paid_alias(intent_id: int):
    payload = request.get_json(silent=True) or {}
    payload["payment_intent_id"] = int(intent_id)
    request._cached_json = (payload, payload)  # noqa: SLF001
    return admin_reject_manual_paid()


@admin_payment_intents_bp.post("/<int:intent_id>/manual/mark-paid")
def admin_mark_manual_paid_alias_root(intent_id: int):
    payload = request.get_json(silent=True) or {}
    payload["payment_intent_id"] = int(intent_id)
    request._cached_json = (payload, payload)  # noqa: SLF001
    return admin_mark_manual_paid()


@admin_payment_intents_bp.post("/<int:intent_id>/manual/reject")
def admin_reject_manual_paid_alias_root(intent_id: int):
    payload = request.get_json(silent=True) or {}
    payload["payment_intent_id"] = int(intent_id)
    request._cached_json = (payload, payload)  # noqa: SLF001
    return admin_reject_manual_paid()
