from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP

from flask import Blueprint, jsonify, request, current_app, g

from app.extensions import db
from app.models import AuditLog, User, PaymentIntent, WebhookEvent, Order
from app.utils.jwt_utils import decode_token
from app.utils.paystack_client import verify_signature
from app.utils.wallets import post_txn
from app.utils.autopilot import get_settings
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

payments_bp = Blueprint("payments_bp", __name__, url_prefix="/api/payments")
admin_payments_bp = Blueprint("admin_payments_bp", __name__, url_prefix="/api/admin/payments")

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


def _manual_instructions_payload() -> dict:
    return {
        "message": "Manual payment mode is enabled. Send proof and await admin confirmation.",
        "account_name": (os.getenv("COMPANY_ACCOUNT_NAME") or "").strip(),
        "account_number": (os.getenv("COMPANY_ACCOUNT_NUMBER") or "").strip(),
        "bank_name": (os.getenv("COMPANY_BANK_NAME") or "").strip(),
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

        if (pi.purpose or "").strip().lower() == "order":
            order_id = _extract_order_id(pi.meta)
            if not order_id:
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
            order = db.session.get(Order, int(order_id))
            if not order:
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
                return {"ok": False, "error": "ORDER_NOT_FOUND", "reference": reference}, 200
            if _order_is_paid(order):
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
                return {"ok": True, "verified": verified, "already_paid": True}, 200

            transition_intent(
                pi,
                PaymentIntentStatus.PAID,
                actor={"type": "webhook"},
                idempotency_key=f"webhook:paystack:{event_id}",
                reason="charge_success",
                metadata={"reference": reference, "source": source},
            )
            _mark_order_paid(order, reference=reference)
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
                    context={"reference": reference, "event_id": event_id, "order_id": int(order.id)},
                    request_id=request_id,
                )
            except Exception:
                db.session.rollback()
            return {"ok": True, "verified": verified, "purpose": "order"}, 200

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

    if payments_mode == "manual_company_account":
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
            pi = _ensure_payment_intent(
                user_id=int(u.id),
                provider="manual_company_account",
                reference=reference,
                purpose=purpose,
                amount=float(amount),
                meta={**meta, "mode": "manual_company_account"},
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
                "reference": pi.reference,
                "authorization_url": None,
                "purpose": purpose,
                "order_id": int(order.id),
                "amount": float(amount),
                "requires_admin_mark_paid": True,
                "manual_instructions": _manual_instructions_payload(),
            }
            if idem_row is not None:
                store_response(idem_row, response, 200)
            return jsonify(response), 200
        except Exception as e:
            db.session.rollback()
            current_app.logger.exception("payments_initialize_manual_failed")
            return jsonify({"ok": False, "error": "PAYMENT_INIT_FAILED", "message": str(e)}), 500

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


@admin_payments_bp.get("/manual/pending")
def admin_manual_pending():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    q = (request.args.get("q") or "").strip().lower()
    limit, offset = _parse_page_values()

    base_query = _manual_pending_filter_query().filter(
        PaymentIntent.status.in_(("manual_pending", "initialized"))
    )
    rows = base_query.order_by(PaymentIntent.created_at.desc()).all()

    items = []
    for row in rows:
        oid = _extract_order_id(row.meta)
        order = db.session.get(Order, int(oid)) if oid else None
        buyer = db.session.get(User, int(order.buyer_id)) if order and order.buyer_id else None

        searchable = " ".join(
            [
                str(row.reference or ""),
                str(oid or ""),
                str(getattr(buyer, "email", "") or ""),
                str(getattr(buyer, "name", "") or ""),
            ]
        ).lower()
        if q and q not in searchable:
            continue

        items.append(
            {
                "intent_id": int(row.id),
                "reference": row.reference or "",
                "status": row.status or "",
                "amount": float(row.amount or 0.0),
                "order_id": int(oid) if oid else None,
                "buyer_id": int(order.buyer_id) if order and order.buyer_id is not None else None,
                "buyer_email": getattr(buyer, "email", "") or "",
                "merchant_id": int(order.merchant_id) if order and order.merchant_id is not None else None,
                "created_at": row.created_at.isoformat() if row.created_at else None,
            }
        )

    total = len(items)
    paged = items[offset:offset + limit]
    return jsonify({"ok": True, "items": paged, "total": total, "limit": limit, "offset": offset}), 200


@admin_payments_bp.post("/manual/mark-paid")
def admin_mark_manual_paid():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    data = request.get_json(silent=True) or {}
    try:
        order_id = int(data.get("order_id"))
    except Exception:
        return jsonify({"ok": False, "message": "order_id required"}), 400

    order = db.session.get(Order, int(order_id))
    if not order:
        return jsonify({"ok": False, "error": "ORDER_NOT_FOUND"}), 404

    if _order_is_paid(order):
        return jsonify({"ok": True, "idempotent": True, "order_id": int(order.id)}), 200

    amount_minor = data.get("amount_minor")
    if amount_minor is not None:
        try:
            expected_minor = int((_order_payment_amount(order) * 100.0))
            provided_minor = int(amount_minor)
        except Exception:
            return jsonify({"ok": False, "message": "amount_minor invalid"}), 400
        if expected_minor != provided_minor:
            return jsonify({"ok": False, "error": "AMOUNT_MISMATCH", "expected_minor": expected_minor, "provided_minor": provided_minor}), 409

    reference = str((data.get("reference") or "")).strip()
    note = str((data.get("note") or "")).strip()
    now_stamp = int(datetime.utcnow().timestamp())

    manual_intent = _find_manual_intent_for_order(int(order.id))
    if not manual_intent:
        fallback_ref = reference or (order.payment_reference or "").strip() or f"FT-MAN-{int(order.id)}-{now_stamp}"
        manual_intent = _ensure_payment_intent(
            user_id=int(order.buyer_id),
            provider="manual_company_account",
            reference=fallback_ref,
            purpose="order",
            amount=float(_json_decimal(_order_payment_amount(order))),
            meta={"purpose": "order", "order_id": int(order.id), "source": "api.admin.payments.manual.mark-paid"},
        )

    final_reference = reference or (manual_intent.reference or "").strip() or (order.payment_reference or "").strip()
    if not final_reference:
        final_reference = f"FT-MAN-{int(order.id)}-{now_stamp}"

    try:
        manual_intent.reference = final_reference
        manual_intent.provider = "manual_company_account"
        manual_intent.purpose = "order"
        manual_intent.meta = json.dumps(
            {
                "purpose": "order",
                "order_id": int(order.id),
                "marked_by_admin_id": int(u.id),
                "note": note[:180],
                "source": "api.admin.payments.manual.mark-paid",
            }
        )
        db.session.add(manual_intent)
        db.session.commit()
        transition_intent(
            manual_intent,
            PaymentIntentStatus.PAID,
            actor={"type": "admin", "id": int(u.id)},
            idempotency_key=f"admin:manual_mark_paid:{int(manual_intent.id)}",
            reason="manual_admin_mark_paid",
            metadata={"reference": final_reference, "order_id": int(order.id)},
        )

        _mark_order_paid(order, reference=final_reference)
        try:
            record_event(
                "manual_mark_paid",
                user=u,
                context={"order_id": int(order.id), "amount": float(_order_payment_amount(order))},
                request_id=_request_id(),
            )
        except Exception:
            db.session.rollback()
        try:
            db.session.add(
                AuditLog(
                    actor_user_id=int(u.id),
                    action="manual_payment_mark_paid",
                    target_type="order",
                    target_id=int(order.id),
                    meta=json.dumps({"reference": final_reference, "note": note[:180]}),
                )
            )
            db.session.commit()
        except Exception:
            db.session.rollback()
        return jsonify({"ok": True, "order_id": int(order.id), "reference": final_reference}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("admin_mark_manual_paid_failed order_id=%s", int(order.id))
        return jsonify({"ok": False, "error": "MANUAL_MARK_PAID_FAILED", "message": str(e)}), 500
