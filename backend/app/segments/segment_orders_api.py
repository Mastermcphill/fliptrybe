from __future__ import annotations

import os
import hmac
import random
import secrets
import uuid
import json
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request, current_app
from sqlalchemy import text, or_

from app.extensions import db
from app.models import (
    User,
    Listing,
    Order,
    OrderEvent,
    Receipt,
    Notification,
    UserSettings,
    MerchantProfile,
    DriverProfile,
    InspectorProfile,
    AvailabilityConfirmation,
    EscrowUnlock,
    QRChallenge,
    InspectionTicket,
    AuditLog,
    CartItem,
    CheckoutBatch,
    PaymentIntent,
)
from app.utils.jwt_utils import decode_token
from app.utils.receipts import create_receipt
from app.utils.commission import compute_commission, resolve_rate, RATES
from app.utils.messaging import enqueue_sms, enqueue_whatsapp
from app.utils.notify import queue_in_app, queue_sms, queue_whatsapp
from app.utils.escrow_unlocks import (
    ensure_unlock,
    hash_code,
    verify_code,
    bump_attempts,
    issue_qr_token,
    verify_qr_token,
    mark_qr_scanned,
    mark_unlock_qr_verified,
    generate_admin_unlock_token,
    hash_admin_unlock_token,
)
from app.jobs.escrow_runner import _hold_order_into_escrow, _refund_escrow
from app.escrow import release_seller_payout, release_driver_payout
from app.jobs.availability_runner import run_availability_timeouts
from app.services.escrow_service import transition_escrow, EscrowStatus
from app.services.risk_engine_service import record_event
from app.utils.autopilot import get_settings
from app.integrations.payments.factory import build_payments_provider
from app.integrations.payments.mock_provider import MockPaymentsProvider
from app.integrations.common import IntegrationDisabledError, IntegrationMisconfiguredError
from app.services.payment_intent_service import transition_intent, PaymentIntentStatus
from app.utils.idempotency import lookup_response, store_response, get_idempotency_key

orders_bp = Blueprint("orders_bp", __name__, url_prefix="/api")


_INIT_DONE = False


@orders_bp.before_app_request
def _ensure_tables_once():
    global _INIT_DONE
    if _INIT_DONE:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _INIT_DONE = True


def _bearer_token() -> str | None:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    return header.replace("Bearer ", "", 1).strip() or None


def _current_user() -> User | None:
    token = _bearer_token()
    if not token:
        return None
    payload = decode_token(token)
    if not payload:
        return None
    sub = payload.get("sub")
    if not sub:
        return None
    try:
        uid = int(sub)
    except Exception:
        return None
    return User.query.get(uid)


def _role(u: User | None) -> str:
    if not u:
        return "guest"
    return (getattr(u, "role", None) or "buyer").strip().lower()


def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    return _role(u) == "admin"


def _is_verified(u: User | None) -> bool:
    if not u:
        return False
    return bool(getattr(u, "is_verified", False))


def _event(order_id: int, actor_id: int | None, event: str, note: str = "") -> None:
    try:
        key = f"order:{int(order_id)}:{event}:{int(actor_id) if actor_id is not None else 'system'}"
        existing = OrderEvent.query.filter_by(idempotency_key=key[:160]).first()
        if existing:
            return
        e = OrderEvent(
            order_id=order_id,
            actor_user_id=actor_id,
            event=event,
            note=note[:240],
            idempotency_key=key[:160],
        )
        db.session.add(e)
        db.session.commit()
    except Exception:
        db.session.rollback()


def _receipt_once(*, user_id: int, kind: str, reference: str, amount: float, description: str, meta: dict):
    """Create a receipt only if one doesn't already exist for (user_id, kind, reference)."""
    try:
        existing = Receipt.query.filter_by(user_id=user_id, kind=kind, reference=reference).first()
        if existing:
            return existing
        rate = float(resolve_rate(kind, state=str(meta.get('state','')) if meta else '', category=str(meta.get('category','')) if meta else ''))
        try:
            if kind == "listing_sale" and (meta or {}).get("role") == "merchant":
                rate = 0.0
        except Exception:
            pass
        fee = compute_commission(amount, rate)
        total = float(amount) + float(fee)
        rec = create_receipt(
            user_id=user_id,
            kind=kind,
            reference=reference,
            amount=amount,
            fee=fee,
            total=total,
            description=description,
            meta={**(meta or {}), "rate": rate},
        )
        db.session.commit()
        return rec
    except Exception:
        db.session.rollback()
        return None


def _notify_user(user_id: int, title: str, body: str, channel: str = "in_app"):
    """Queue a notification respecting user settings (demo sender later flushes)."""
    try:
        settings = UserSettings.query.filter_by(user_id=user_id).first()
        if settings:
            if channel == "sms" and not bool(settings.notif_sms):
                return
            if channel == "whatsapp" and not bool(settings.notif_whatsapp):
                return
            if channel == "in_app" and not bool(settings.notif_in_app):
                return
        n = Notification(user_id=user_id, channel=channel, title=title[:140], body=body, status="queued")
        db.session.add(n)
        db.session.commit()
    except Exception:
        db.session.rollback()


def _parse_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return int(value) == 1
    if isinstance(value, str):
        return value.strip().lower() in ("1", "true", "yes", "y")
    return False

def _gen_delivery_code() -> str:
    # 4-digit code, avoid leading zeros confusion by allowing them but formatting fixed length
    try:
        return f"{random.randint(0, 9999):04d}"
    except Exception:
        return "0000"


def _public_base_url() -> str:
    base = (os.getenv("PUBLIC_BASE_URL") or os.getenv("BASE_URL") or "").strip()
    return base.rstrip("/") if base else ""


def _availability_url(kind: str, token: str) -> str:
    path = f"/api/availability/{kind}?token={token}"
    base = _public_base_url()
    return f"{base}{path}" if base else path


def _availability_message(token: str) -> str:
    yes_url = _availability_url("confirm", token)
    no_url = _availability_url("deny", token)
    return f"FlipTrybe: Is this item still available? YES: {yes_url} NO: {no_url}. Expires in 2 hours."


def _ensure_codes(order: Order) -> bool:
    changed = False
    if not (order.pickup_code or "").strip():
        order.pickup_code = _gen_delivery_code()
        changed = True
    if not (order.dropoff_code or "").strip():
        order.dropoff_code = _gen_delivery_code()
        changed = True
    return changed


def _send_code_sms(user: User | None, message: str, reference: str) -> None:
    try:
        if user:
            queue_sms(int(user.id), "FlipTrybe", message, meta={"ref": reference})
            queue_whatsapp(int(user.id), "FlipTrybe", message, meta={"ref": reference})
    except Exception:
        pass


def _issue_pickup_unlock(order: Order) -> None:
    unlock = ensure_unlock(int(order.id), "pickup_seller")
    _ensure_codes(order)
    code = (order.pickup_code or "").strip()
    if code:
        unlock.code_hash = hash_code(int(order.id), "pickup_seller", code)
    if code and order.driver_id:
        try:
            driver = User.query.get(int(order.driver_id))
        except Exception:
            driver = None
        msg = f"FlipTrybe: Pickup code for Order #{int(order.id)} is {code}. Keep private."
        _send_code_sms(driver, msg, reference=f"order:{int(order.id)}:pickup_code:sms:driver")


def _issue_delivery_unlock(order: Order) -> None:
    unlock = ensure_unlock(int(order.id), "delivery_driver")
    _ensure_codes(order)
    code = (order.dropoff_code or "").strip()
    if code:
        unlock.code_hash = hash_code(int(order.id), "delivery_driver", code)
    if code:
        try:
            buyer = User.query.get(int(order.buyer_id))
        except Exception:
            buyer = None
        msg = f"FlipTrybe: Delivery code for Order #{int(order.id)} is {code}. Share only with the driver."
        _send_code_sms(buyer, msg, reference=f"order:{int(order.id)}:delivery_code:sms:buyer")


def _qr_roles(step: str) -> tuple[str, str]:
    if step == "pickup_seller":
        return "driver", "seller"
    if step == "delivery_driver":
        return "buyer", "driver"
    return "inspector", "seller"


def _availability_for_order(order_id: int) -> AvailabilityConfirmation | None:
    try:
        return AvailabilityConfirmation.query.filter_by(order_id=int(order_id)).first()
    except Exception:
        return None


def _availability_is_confirmed(order_id: int) -> bool:
    row = _availability_for_order(order_id)
    return bool(row and (row.status or "") == "yes")


def _queue_availability_notifications(order: Order, token: str, recipient_ids: list[int]) -> None:
    title = "Availability Check"
    msg = _availability_message(token)
    for uid in recipient_ids:
        try:
            queue_in_app(int(uid), title, msg, meta={"order_id": int(order.id)})
            queue_sms(int(uid), title, msg, meta={"order_id": int(order.id)})
            queue_whatsapp(int(uid), title, msg, meta={"order_id": int(order.id)})
        except Exception:
            pass


def _ensure_availability_request(order: Order, listing: Listing | None, merchant_id: int, seller_id: int | None) -> AvailabilityConfirmation:
    existing = _availability_for_order(int(order.id))
    if existing:
        return existing

    token = secrets.token_urlsafe(32)
    requested_at = datetime.utcnow()
    deadline_at = requested_at + timedelta(hours=2)

    row = AvailabilityConfirmation(
        order_id=int(order.id),
        listing_id=int(listing.id) if listing else None,
        merchant_id=int(merchant_id) if merchant_id else None,
        seller_id=int(seller_id) if seller_id else None,
        status="pending",
        requested_at=requested_at,
        deadline_at=deadline_at,
        response_token=token,
    )
    db.session.add(row)
    db.session.commit()

    recipients = []
    if merchant_id:
        recipients.append(int(merchant_id))
    if seller_id and int(seller_id) not in recipients:
        recipients.append(int(seller_id))

    _queue_availability_notifications(order, token, recipients)
    try:
        db.session.commit()
    except Exception:
        # Notification queue drift should not break order state transitions.
        db.session.rollback()
    return row


def _user_contact(user: User | None, fallback_phone: str = "") -> dict:
    if not user:
        return {"name": "", "phone": fallback_phone or ""}
    phone = getattr(user, "phone", None) or fallback_phone or ""
    return {"name": user.name or "", "phone": phone}


def _seller_address(order: Order, listing: Listing | None, profile: MerchantProfile | None) -> str:
    parts = []
    if profile:
        for piece in (profile.locality, profile.city, profile.state, profile.lga):
            if piece:
                parts.append(str(piece).strip())
    if not parts and listing:
        for piece in (listing.locality, listing.city, listing.state):
            if piece:
                parts.append(str(piece).strip())
    if not parts and (order.pickup or "").strip():
        parts.append(order.pickup.strip())
    return ", ".join([p for p in parts if p])


def _driver_details(driver: User | None) -> dict:
    if not driver:
        return {"name": "", "phone": "", "vehicle_type": "", "plate_number": "", "color": "", "model": "", "photo": ""}
    prof = DriverProfile.query.filter_by(user_id=int(driver.id)).first()
    phone = (prof.phone if prof and prof.phone else getattr(driver, "phone", None) or "")
    return {
        "name": driver.name or "",
        "phone": phone or "",
        "vehicle_type": prof.vehicle_type if prof else "",
        "plate_number": prof.plate_number if prof else "",
        "color": "",
        "model": "",
        "photo": "",
    }


def _inspector_details(inspector: User | None) -> dict:
    if not inspector:
        return {"name": "", "phone": "", "photo": ""}
    prof = InspectorProfile.query.filter_by(user_id=int(inspector.id)).first()
    phone = (prof.phone if prof and prof.phone else getattr(inspector, "phone", None) or "")
    return {"name": inspector.name or "", "phone": phone or "", "photo": ""}


def _reveal_for_user(order: Order, viewer: User, listing: Listing | None) -> dict:
    buyer = User.query.get(int(order.buyer_id)) if order.buyer_id else None
    seller = User.query.get(int(order.merchant_id)) if order.merchant_id else None
    driver = User.query.get(int(order.driver_id)) if order.driver_id else None
    inspector = User.query.get(int(order.inspector_id)) if order.inspector_id else None

    profile = MerchantProfile.query.filter_by(user_id=int(order.merchant_id)).first() if order.merchant_id else None

    is_admin = _is_admin(viewer)
    is_buyer = int(order.buyer_id) == int(viewer.id)
    is_seller = int(order.merchant_id) == int(viewer.id)
    is_driver = order.driver_id is not None and int(order.driver_id) == int(viewer.id)
    is_inspector = order.inspector_id is not None and int(order.inspector_id) == int(viewer.id)

    mode = (order.fulfillment_mode or "unselected").lower()
    reveal = {"mode": mode, "order_id": int(order.id)}

    seller_address = _seller_address(order, listing, profile)

    if is_admin or is_buyer:
        reveal["seller"] = {**_user_contact(seller), "address": seller_address}
    if is_admin or is_seller:
        reveal["buyer"] = _user_contact(buyer)
    if is_admin or is_driver:
        reveal["buyer"] = _user_contact(buyer)
        reveal["seller"] = {**_user_contact(seller), "address": seller_address}
        reveal["pickup"] = (order.pickup or "")
        reveal["dropoff"] = (order.dropoff or "")

    if mode == "delivery":
        if is_admin or is_buyer or is_seller:
            reveal["driver"] = _driver_details(driver)
    if mode == "inspection":
        if is_admin or is_buyer or is_seller:
            reveal["inspector"] = _inspector_details(inspector)

    return reveal


def _mark_paid(order: Order, reference: str | None = None, actor_id: int | None = None) -> None:
    if reference:
        order.payment_reference = reference
    order.status = "paid"
    if order.inspection_required:
        order.release_condition = "INSPECTION_PASS"
    else:
        order.release_condition = "BUYER_CONFIRM"
    _hold_order_into_escrow(order)
    try:
        transition_escrow(
            order,
            EscrowStatus.HELD,
            idempotency_key=f"order_paid_hold:{int(order.id)}:{(reference or '')[:40]}",
            actor={"type": "system" if actor_id is None else "user", "id": actor_id},
            reason="payment_marked_paid",
            metadata={"reference": reference or "", "order_id": int(order.id)},
        )
    except Exception:
        pass
    # Do NOT release escrow at payment. Availability + secret-code confirmations gate release.

    try:
        listing = Listing.query.get(int(order.listing_id)) if order.listing_id else None
    except Exception:
        listing = None
    seller_id = None
    if listing:
        try:
            seller_id = int(getattr(listing, "user_id") or 0) or None
        except Exception:
            seller_id = None

    _ensure_availability_request(order, listing, int(order.merchant_id), seller_id)
    # Notify buyer & merchant via SMS/WhatsApp (trust layer) when payment is confirmed
    try:
        buyer = User.query.get(int(order.buyer_id))
        merchant = User.query.get(int(order.merchant_id))
        msg_buyer = f"FlipTrybe: Payment confirmed for Order #{int(order.id)}. Delivery code will be sent after pickup."
        msg_merchant = f"FlipTrybe: Sale confirmed for Order #{int(order.id)}. Prepare item for dispatch." 
        if buyer and getattr(buyer, 'phone', None):
            enqueue_sms(buyer.phone, msg_buyer, reference=f"order:{int(order.id)}:paid:sms:buyer")
            enqueue_whatsapp(buyer.phone, msg_buyer, reference=f"order:{int(order.id)}:paid:wa:buyer")
        if merchant and getattr(merchant, 'phone', None):
            enqueue_sms(merchant.phone, msg_merchant, reference=f"order:{int(order.id)}:paid:sms:merchant")
            enqueue_whatsapp(merchant.phone, msg_merchant, reference=f"order:{int(order.id)}:paid:wa:merchant")
    except Exception:
        pass
    if actor_id is not None:
        try:
            _event(int(order.id), int(actor_id), "paid", "Order marked paid")
        except Exception:
            pass


def _money_to_minor(amount: float | Decimal | int | None) -> int:
    try:
        parsed = Decimal(str(amount or 0))
    except Exception:
        parsed = Decimal("0")
    return int((parsed * Decimal("100")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _minor_to_money(amount_minor: int | None) -> float:
    try:
        return float((Decimal(int(amount_minor or 0)) / Decimal("100")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))
    except Exception:
        return 0.0


def _cart_item_payload(item: CartItem, listing: Listing | None) -> dict:
    return {
        "id": int(item.id),
        "listing_id": int(item.listing_id),
        "quantity": int(item.quantity or 1),
        "unit_price_minor": int(item.unit_price_minor or 0),
        "unit_price": _minor_to_money(item.unit_price_minor),
        "line_total_minor": int((item.unit_price_minor or 0) * int(item.quantity or 1)),
        "line_total": _minor_to_money((item.unit_price_minor or 0) * int(item.quantity or 1)),
        "listing": listing.to_dict() if listing else None,
    }


def _payments_mode(settings) -> str:
    mode = (getattr(settings, "payments_mode", None) or "").strip().lower()
    if mode in ("wallet", "paystack_auto", "manual_company_account", "mock"):
        return mode
    provider = (getattr(settings, "payments_provider", "mock") or "mock").strip().lower()
    return "mock" if provider == "mock" else "paystack_auto"


def _paystack_available(settings) -> bool:
    mode = _payments_mode(settings)
    if mode == "mock":
        return True
    provider = (getattr(settings, "payments_provider", "mock") or "mock").strip().lower()
    enabled = bool(getattr(settings, "paystack_enabled", False))
    return mode == "paystack_auto" and provider != "mock" and enabled


def _manual_instructions_from_settings(settings) -> dict:
    return {
        "mode": "bank_transfer_manual",
        "bank_name": (getattr(settings, "manual_payment_bank_name", "") or "").strip() or (os.getenv("FLIPTRYBE_BANK_NAME") or "").strip(),
        "account_number": (getattr(settings, "manual_payment_account_number", "") or "").strip() or (os.getenv("FLIPTRYBE_BANK_ACCOUNT_NUMBER") or "").strip(),
        "account_name": (getattr(settings, "manual_payment_account_name", "") or "").strip() or (os.getenv("FLIPTRYBE_BANK_ACCOUNT_NAME") or "").strip(),
        "note": (getattr(settings, "manual_payment_note", "") or "").strip(),
        "sla_minutes": int(getattr(settings, "manual_payment_sla_minutes", 360) or 360),
        "message": "Manual transfer enabled. Transfer exact amount and keep your reference.",
    }


def _settle_wallet_batch(*, buyer_id: int, total_minor: int, reference: str, order_ids: list[int], actor_id: int) -> None:
    amount = _minor_to_money(total_minor)
    for oid in order_ids:
        order = db.session.get(Order, int(oid))
        if not order:
            continue
        _mark_paid(order, reference=reference, actor_id=actor_id)
    if amount > 0:
        post_ref = f"wallet_purchase:{reference}"
        try:
            from app.utils.wallets import post_txn
            post_txn(int(buyer_id), amount, kind="purchase", direction="debit", reference=post_ref)
        except Exception:
            db.session.rollback()



@orders_bp.post("/orders")
def create_order():
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401

    debug_requested = (request.headers.get("X-Debug", "").strip() == "1")
    debug_for_user = debug_requested and (u is not None)
    debug_for_admin = debug_for_user and _is_admin(u)

    payload = request.get_json(silent=True) or {}
    payload_source = "json" if payload else "empty"
    if not payload:
        form_data = request.form.to_dict(flat=True) if request.form else {}
        args_data = request.args.to_dict(flat=True) if request.args else {}
        payload = {**args_data, **form_data}
        payload_source = "form_args" if payload else "empty"

    def _debug_payload(extra: dict | None = None) -> dict:
        if not debug_for_admin:
            return {}
        out = {
            "debug": {
                "keys": sorted([str(k) for k in payload.keys()]),
                "payload_source": payload_source,
            }
        }
        if extra:
            out["debug"].update(extra)
        return out

    def _safe_snippet(value, limit: int = 500):
        try:
            if value is None:
                return ""
            text_value = str(value)
            return text_value[:limit]
        except Exception:
            return ""

    def _debug_exception_payload(e: Exception) -> dict:
        detail = _safe_snippet(f"{type(e).__name__}: {e}", 800)
        out = {"detail": detail, "payload_source": payload_source}
        if debug_for_admin:
            sql = _safe_snippet(getattr(e, "statement", ""))
            if sql:
                out["sql"] = sql
            params = _safe_snippet(getattr(e, "params", None))
            if params:
                out["params"] = params
        return out

    def _parse_money(raw_value, field_name: str, *, required: bool = False) -> Decimal | None:
        if raw_value is None:
            if required:
                raise ValueError(f"{field_name} required")
            return None
        text_value = str(raw_value).strip()
        if text_value == "":
            if required:
                raise ValueError(f"{field_name} required")
            return None
        try:
            parsed = Decimal(text_value)
        except (InvalidOperation, TypeError, ValueError):
            raise ValueError(f"{field_name} invalid")
        return parsed.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

    buyer_id_raw = payload.get("buyer_id")
    try:
        buyer_id = int(buyer_id_raw or u.id)
    except Exception:
        buyer_id = int(u.id)

    if _is_admin(u) and not buyer_id_raw:
        return jsonify({"ok": False, "message": "buyer_id required for admin", **_debug_payload({
            "buyer_id_raw": buyer_id_raw,
        })}), 400

    if buyer_id != int(u.id) and not _is_admin(u):
        return jsonify({"ok": False, "message": "Forbidden"}), 403

    listing_obj = payload.get("listing") if isinstance(payload.get("listing"), dict) else {}
    listing_id = payload.get("listing_id")
    if listing_id is None:
        listing_id = payload.get("listingId")
    if listing_id is None and listing_obj:
        listing_id = listing_obj.get("id")
    try:
        listing_id_int = int(listing_id) if listing_id is not None else None
    except Exception:
        listing_id_int = None
    if listing_id_int is None:
        return jsonify({"ok": False, "message": "listing_id required", **_debug_payload({
            "listing_id_raw": listing_id,
        })}), 400

    # Listing is authoritative for merchant ownership.
    listing = Listing.query.get(listing_id_int) if listing_id_int else None
    if listing_id_int and not listing:
        return jsonify({"ok": False, "message": "listing not found"}), 404

    listing_merchant_id = None
    if listing:
        try:
            if getattr(listing, "user_id", None) is not None:
                listing_merchant_id = int(getattr(listing, "user_id"))
            elif getattr(listing, "merchant_id", None) is not None:
                listing_merchant_id = int(getattr(listing, "merchant_id"))
        except Exception:
            listing_merchant_id = None

    merchant_obj = payload.get("merchant") if isinstance(payload.get("merchant"), dict) else {}
    merchant_id_raw = payload.get("merchant_id")
    if merchant_id_raw is None:
        merchant_id_raw = payload.get("merchantId")
    if merchant_id_raw is None and merchant_obj:
        merchant_id_raw = merchant_obj.get("id")
    if merchant_id_raw is None and listing_obj:
        merchant_id_raw = listing_obj.get("merchant_id") or listing_obj.get("merchantId") or listing_obj.get("user_id")
    merchant_id = None
    if merchant_id_raw is None or str(merchant_id_raw).strip() == "":
        merchant_id = listing_merchant_id
    else:
        try:
            merchant_id = int(merchant_id_raw)
        except Exception:
            return jsonify({"ok": False, "message": "merchant_id invalid", **_debug_payload({
                "merchant_id_raw": merchant_id_raw,
            })}), 400

    if listing_merchant_id is not None and merchant_id is not None and int(merchant_id) != int(listing_merchant_id):
        return jsonify({"ok": False, "message": "merchant_id must match listing owner", **_debug_payload({
            "merchant_id_raw": merchant_id_raw,
            "listing_merchant_id": listing_merchant_id,
        })}), 400

    if merchant_id is None:
        return jsonify({"ok": False, "message": "merchant_id unavailable for listing", **_debug_payload({
            "merchant_id_raw": merchant_id_raw,
            "listing_merchant_id": listing_merchant_id,
        })}), 400

    try:
        amount_dec = _parse_money(payload.get("amount"), "amount", required=False)
        delivery_fee_dec = _parse_money(payload.get("delivery_fee"), "delivery_fee", required=False) or Decimal("0.00")
        inspection_fee_dec = _parse_money(payload.get("inspection_fee"), "inspection_fee", required=False) or Decimal("0.00")
    except ValueError as parse_error:
        return jsonify({"ok": False, "message": str(parse_error), **_debug_payload()}), 400

    pickup = (payload.get("pickup") or "").strip()
    dropoff = (payload.get("dropoff") or "").strip()
    payment_reference = (payload.get("payment_reference") or "").strip()
    inspection_required = _parse_bool(payload.get("inspection_required"))

    # Idempotency: same payment reference + same buyer/merchant/listing returns existing order.
    if payment_reference:
        existing = Order.query.filter_by(payment_reference=payment_reference).order_by(Order.id.asc()).first()
        if existing:
            same_buyer = int(existing.buyer_id or 0) == int(buyer_id)
            same_merchant = int(existing.merchant_id or 0) == int(merchant_id)
            same_listing = (int(existing.listing_id) if existing.listing_id is not None else None) == (
                int(listing_id_int) if listing_id_int is not None else None
            )
            if same_buyer and same_merchant and same_listing:
                return jsonify({"ok": True, "order": existing.to_dict(), "idempotent": True}), 200
            return jsonify({"ok": False, "message": "payment_reference already used"}), 409

    if listing and hasattr(listing, "is_active") and not bool(getattr(listing, "is_active")):
        return jsonify({"ok": False, "message": "Listing is no longer available"}), 409

    # Seller cannot buy their own listing
    try:
        seller_id_for_check = listing_merchant_id if listing_merchant_id is not None else merchant_id
        if seller_id_for_check is not None and int(buyer_id) == int(seller_id_for_check) and not _is_admin(u):
            return jsonify({
                "ok": False,
                "error": "SELLER_CANNOT_BUY_OWN_LISTING",
                "message": "You cannot place an order on a listing you own",
            }), 409
    except Exception:
        pass

    if not _is_admin(u) and not _is_verified(u):
        return jsonify({
            "ok": False,
            "error": "EMAIL_NOT_VERIFIED",
            "message": "Your email must be verified to perform this action",
        }), 403

# If listing provided, prefer listing pricing rules over payload amount
    if listing:
        try:
            seller = User.query.get(int(merchant_id))
            seller_role = (getattr(seller, "role", "") or "buyer").strip().lower()
            if seller_role in ("driver", "inspector"):
                seller_role = "merchant"
        except Exception:
            seller_role = "buyer"

        try:
            base_price = Decimal(str(getattr(listing, "base_price", 0.0) or 0.0))
        except Exception:
            base_price = Decimal("0.00")
        if base_price <= 0:
            try:
                base_price = Decimal(str(getattr(listing, "price", 0.0) or 0.0))
            except Exception:
                base_price = Decimal("0.00")
        try:
            platform_fee = Decimal(str(getattr(listing, "platform_fee", 0.0) or 0.0))
        except Exception:
            platform_fee = Decimal("0.00")
        try:
            final_price = Decimal(str(getattr(listing, "final_price", 0.0) or 0.0))
        except Exception:
            final_price = Decimal("0.00")

        base_price = base_price.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        platform_fee = platform_fee.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        final_price = final_price.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

        if seller_role == "merchant":
            if platform_fee <= 0:
                platform_fee = (base_price * Decimal("0.03")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
            if final_price <= 0:
                final_price = (base_price + platform_fee).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
            amount_dec = final_price
        else:
            amount_dec = base_price

    if amount_dec is None:
        return jsonify({"ok": False, "message": "amount required", **_debug_payload({
            "amount_raw": payload.get("amount"),
        })}), 400

    amount_dec = amount_dec.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    if amount_dec < 0 or delivery_fee_dec < 0 or inspection_fee_dec < 0:
        return jsonify({"ok": False, "message": "amount values must be non-negative", **_debug_payload()}), 400

    total_price_dec = (amount_dec + delivery_fee_dec + inspection_fee_dec).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    amount = float(amount_dec)
    delivery_fee = float(delivery_fee_dec)
    inspection_fee = float(inspection_fee_dec)
    total_price = float(total_price_dec)

    if buyer_id is None or listing_id_int is None or merchant_id is None:
        return jsonify({"ok": False, "message": "buyer_id, listing_id, and merchant_id are required", **_debug_payload({
            "buyer_id_raw": buyer_id_raw,
            "listing_id_raw": listing_id,
            "merchant_id_raw": merchant_id_raw,
        })}), 400

    handshake_id = (payload.get("handshake_id") or "").strip()
    if not handshake_id:
        handshake_id = str(uuid.uuid4())

    order = Order(
        buyer_id=buyer_id,
        merchant_id=merchant_id,
        listing_id=listing_id_int,
        amount=amount,
        total_price=total_price,
        delivery_fee=delivery_fee,
        inspection_fee=inspection_fee,
        pickup=pickup,
        dropoff=dropoff,
        payment_reference=payment_reference,
        inspection_required=inspection_required,
        status="created",
        updated_at=datetime.utcnow(),
        handshake_id=handshake_id,
    )

    try:
        db.session.add(order)
        db.session.commit()
        if payment_reference:
            try:
                _mark_paid(order, payment_reference, actor_id=int(u.id))
                order.updated_at = datetime.utcnow()
                db.session.add(order)
                db.session.commit()
            except Exception:
                db.session.rollback()
                try:
                    current_app.logger.exception(
                        "orders.create_mark_paid_side_effect_failed order_id=%s user_id=%s",
                        int(getattr(order, "id", 0) or 0),
                        int(getattr(u, "id", 0) or 0),
                    )
                except Exception:
                    pass
        _event(order.id, u.id, "created", "Order created")
        _notify_user(int(order.merchant_id), "New Order", f"You received a new order #{int(order.id)}")
        _notify_user(int(order.buyer_id), "Order Created", f"Your order #{int(order.id)} was created")
        return jsonify({"ok": True, "order": order.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        try:
            current_app.logger.exception(
                "orders.create_failed buyer_id=%s merchant_id=%s user_id=%s",
                int(buyer_id),
                int(merchant_id),
                int(getattr(u, "id", 0) or 0),
            )
        except Exception:
            pass
        if debug_for_user:
            return jsonify({"ok": False, "error": "db_error", **_debug_exception_payload(e), **_debug_payload({
                "listing_id_raw": listing_id,
                "merchant_id_raw": merchant_id_raw,
                "buyer_id_raw": buyer_id_raw,
            })}), 500
        return jsonify({"ok": False, "error": "db_error"}), 500


@orders_bp.get("/cart")
def get_cart():
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401
    rows = CartItem.query.filter_by(user_id=int(u.id)).order_by(CartItem.created_at.desc()).all()
    listing_ids = [int(row.listing_id) for row in rows]
    listing_map = {}
    if listing_ids:
        for listing in Listing.query.filter(Listing.id.in_(listing_ids)).all():
            listing_map[int(listing.id)] = listing
    items = [_cart_item_payload(row, listing_map.get(int(row.listing_id))) for row in rows]
    total_minor = sum(int(item.get("line_total_minor") or 0) for item in items)
    return jsonify({"ok": True, "items": items, "total_minor": total_minor, "total": _minor_to_money(total_minor)}), 200


@orders_bp.post("/cart/items")
def add_cart_item():
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    try:
        listing_id = int(payload.get("listing_id"))
    except Exception:
        return jsonify({"ok": False, "message": "listing_id required"}), 400
    try:
        quantity = int(payload.get("quantity") or 1)
    except Exception:
        quantity = 1
    if quantity < 1:
        quantity = 1
    if quantity > 20:
        quantity = 20
    listing = db.session.get(Listing, int(listing_id))
    if not listing:
        return jsonify({"ok": False, "message": "listing not found"}), 404
    if hasattr(listing, "is_active") and not bool(getattr(listing, "is_active")):
        return jsonify({"ok": False, "message": "listing unavailable"}), 409
    unit_price_minor = _money_to_minor(getattr(listing, "final_price", None) or getattr(listing, "price", 0.0))
    row = CartItem.query.filter_by(user_id=int(u.id), listing_id=int(listing.id)).first()
    if row is None:
        row = CartItem(
            user_id=int(u.id),
            listing_id=int(listing.id),
            quantity=int(quantity),
            unit_price_minor=int(unit_price_minor),
            updated_at=datetime.utcnow(),
        )
    else:
        row.quantity = int(quantity)
        row.unit_price_minor = int(unit_price_minor)
        row.updated_at = datetime.utcnow()
    try:
        db.session.add(row)
        db.session.commit()
        return jsonify({"ok": True, "item": _cart_item_payload(row, listing)}), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "CART_ADD_FAILED", "message": str(exc)}), 500


@orders_bp.patch("/cart/items/<int:item_id>")
def update_cart_item(item_id: int):
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401
    row = CartItem.query.filter_by(id=int(item_id), user_id=int(u.id)).first()
    if not row:
        return jsonify({"ok": False, "message": "Cart item not found"}), 404
    payload = request.get_json(silent=True) or {}
    try:
        quantity = int(payload.get("quantity") or row.quantity or 1)
    except Exception:
        quantity = int(row.quantity or 1)
    if quantity < 1:
        quantity = 1
    if quantity > 20:
        quantity = 20
    row.quantity = int(quantity)
    row.updated_at = datetime.utcnow()
    try:
        db.session.add(row)
        db.session.commit()
        listing = db.session.get(Listing, int(row.listing_id))
        return jsonify({"ok": True, "item": _cart_item_payload(row, listing)}), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "CART_UPDATE_FAILED", "message": str(exc)}), 500


@orders_bp.delete("/cart/items/<int:item_id>")
def delete_cart_item(item_id: int):
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401
    row = CartItem.query.filter_by(id=int(item_id), user_id=int(u.id)).first()
    if not row:
        return jsonify({"ok": False, "message": "Cart item not found"}), 404
    try:
        db.session.delete(row)
        db.session.commit()
        return jsonify({"ok": True, "deleted": True, "id": int(item_id)}), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "CART_DELETE_FAILED", "message": str(exc)}), 500


@orders_bp.post("/orders/bulk")
def create_orders_bulk():
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401
    settings = get_settings()
    if not bool(getattr(settings, "cart_checkout_v1", False)) and not _is_admin(u):
        return jsonify({"ok": False, "error": "FEATURE_DISABLED", "message": "Cart checkout is not enabled yet"}), 503
    idem_key = get_idempotency_key()
    if not idem_key:
        return jsonify({"ok": False, "message": "Idempotency-Key required"}), 400
    payload = request.get_json(silent=True) or {}
    payment_method = str(payload.get("payment_method") or "wallet").strip().lower()
    if payment_method == "paystack":
        payment_method = "paystack_card"
    if payment_method not in ("wallet", "paystack_card", "paystack_transfer", "bank_transfer_manual"):
        return jsonify(
            {
                "ok": False,
                "message": "payment_method must be wallet|paystack_card|paystack_transfer|bank_transfer_manual",
            }
        ), 400
    if payment_method == "bank_transfer_manual" and _paystack_available(settings):
        return jsonify(
            {
                "ok": False,
                "error": "PAYMENT_METHOD_UNAVAILABLE",
                "message": "Manual transfer is unavailable while Paystack auto mode is active.",
            }
        ), 409
    if payment_method in ("paystack_card", "paystack_transfer") and not _paystack_available(settings):
        return jsonify(
            {
                "ok": False,
                "error": "INTEGRATION_DISABLED",
                "message": "Paystack checkout is unavailable in current mode.",
            }
        ), 503

    idem = lookup_response(int(u.id), "/api/orders/bulk", payload)
    if idem and idem[0] == "hit":
        return jsonify(idem[1]), idem[2]
    if idem and idem[0] == "conflict":
        return jsonify(idem[1]), idem[2]
    idem_row = idem[1] if idem and idem[0] == "miss" else None

    listing_ids_payload = payload.get("listing_ids")
    listing_ids: list[int] = []
    if isinstance(listing_ids_payload, list) and listing_ids_payload:
        for value in listing_ids_payload:
            try:
                listing_ids.append(int(value))
            except Exception:
                continue
    if not listing_ids:
        rows = CartItem.query.filter_by(user_id=int(u.id)).order_by(CartItem.created_at.desc()).all()
        listing_ids = [int(row.listing_id) for row in rows]
    if not listing_ids:
        return jsonify({"ok": False, "message": "listing_ids required"}), 400

    listings = Listing.query.filter(Listing.id.in_(listing_ids)).all()
    listing_map = {int(row.id): row for row in listings}
    missing = [lid for lid in listing_ids if lid not in listing_map]
    if missing:
        return jsonify({"ok": False, "message": "listing not found", "missing_listing_ids": missing}), 404

    orders: list[Order] = []
    total_minor = 0
    for lid in listing_ids:
        listing = listing_map[int(lid)]
        if hasattr(listing, "is_active") and not bool(getattr(listing, "is_active")):
            return jsonify({"ok": False, "message": "listing unavailable", "listing_id": int(lid)}), 409
        merchant_id = int(getattr(listing, "user_id", 0) or 0)
        if merchant_id <= 0:
            return jsonify({"ok": False, "message": "listing owner missing", "listing_id": int(lid)}), 409
        if int(merchant_id) == int(u.id):
            return jsonify({"ok": False, "error": "SELLER_CANNOT_BUY_OWN_LISTING", "message": "You cannot place an order on a listing you own", "listing_id": int(lid)}), 409
        amount = float(getattr(listing, "final_price", None) or getattr(listing, "price", 0.0) or 0.0)
        if amount <= 0:
            return jsonify({"ok": False, "message": "invalid listing price", "listing_id": int(lid)}), 409
        order = Order(
            buyer_id=int(u.id),
            merchant_id=int(merchant_id),
            listing_id=int(lid),
            amount=float(amount),
            total_price=float(amount),
            delivery_fee=0.0,
            inspection_fee=0.0,
            status="created",
            updated_at=datetime.utcnow(),
            handshake_id=str(uuid.uuid4()),
        )
        db.session.add(order)
        orders.append(order)
        total_minor += _money_to_minor(amount)

    try:
        db.session.commit()
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "ORDER_BATCH_CREATE_FAILED", "message": str(exc)}), 500

    order_ids = [int(row.id) for row in orders]
    batch = CheckoutBatch(
        user_id=int(u.id),
        status="created",
        payment_method=payment_method,
        total_minor=int(total_minor),
        currency="NGN",
        payment_intent_id=None,
        order_ids_json=json.dumps(order_ids),
        idempotency_key=str(idem_key)[:128],
        updated_at=datetime.utcnow(),
    )
    db.session.add(batch)
    db.session.commit()

    response: dict
    if payment_method == "wallet":
        reference = f"FT-WAL-BATCH-{int(batch.id)}-{int(datetime.utcnow().timestamp())}"
        try:
            _settle_wallet_batch(
                buyer_id=int(u.id),
                total_minor=int(total_minor),
                reference=reference,
                order_ids=order_ids,
                actor_id=int(u.id),
            )
            for order in orders:
                order.payment_reference = reference
                db.session.add(order)
            batch.status = "paid"
            batch.updated_at = datetime.utcnow()
            db.session.add(batch)
            db.session.commit()
            response = {
                "ok": True,
                "mode": "wallet",
                "payment_method": "wallet",
                "batch_id": int(batch.id),
                "order_ids": order_ids,
                "total_minor": int(total_minor),
                "total": _minor_to_money(total_minor),
                "status": "paid",
            }
        except Exception as exc:
            db.session.rollback()
            return jsonify({"ok": False, "error": "WALLET_CHECKOUT_FAILED", "message": str(exc)}), 500
    elif payment_method == "bank_transfer_manual":
        settings = get_settings()
        reference = f"FT-MAN-BATCH-{int(batch.id)}-{int(datetime.utcnow().timestamp())}"
        pi = PaymentIntent(
            user_id=int(u.id),
            provider="manual_company_account",
            reference=reference,
            purpose="order",
            amount=_minor_to_money(total_minor),
            amount_minor=int(total_minor),
            status=PaymentIntentStatus.INITIALIZED,
            updated_at=datetime.utcnow(),
            meta=json.dumps(
                {
                    "purpose": "order",
                    "order_ids": order_ids,
                    "batch_id": int(batch.id),
                    "initiated_by": int(u.id),
                    "payment_method": "bank_transfer_manual",
                }
            ),
        )
        db.session.add(pi)
        db.session.commit()
        transition_intent(
            pi,
            PaymentIntentStatus.MANUAL_PENDING,
            actor={"type": "user", "id": int(u.id)},
            idempotency_key=f"init:{pi.reference}:manual_pending",
            reason="manual_initialize_bulk",
            metadata={"order_ids": order_ids, "batch_id": int(batch.id)},
        )
        for order in orders:
            order.payment_reference = pi.reference
            db.session.add(order)
        batch.payment_intent_id = int(pi.id)
        batch.status = "manual_pending"
        batch.updated_at = datetime.utcnow()
        db.session.add(batch)
        db.session.commit()
        response = {
            "ok": True,
            "mode": "bank_transfer_manual",
            "payment_method": "bank_transfer_manual",
            "batch_id": int(batch.id),
            "payment_intent_id": int(pi.id),
            "order_ids": order_ids,
            "reference": pi.reference,
            "total_minor": int(total_minor),
            "total": _minor_to_money(total_minor),
            "manual_instructions": _manual_instructions_from_settings(settings),
            "status": "manual_pending",
        }
    else:
        settings = get_settings()
        payments_mode = _payments_mode(settings)
        if payments_mode == "manual_company_account":
            return jsonify({"ok": False, "error": "INTEGRATION_DISABLED", "message": "Paystack checkout disabled while manual mode is active"}), 503
        provider = MockPaymentsProvider() if payments_mode == "mock" else None
        if provider is None:
            try:
                provider = build_payments_provider(settings)
            except IntegrationDisabledError as exc:
                return jsonify({"ok": False, "error": "INTEGRATION_DISABLED", "message": str(exc)}), 503
            except IntegrationMisconfiguredError as exc:
                return jsonify({"ok": False, "error": "INTEGRATION_MISCONFIGURED", "message": str(exc)}), 500
        reference = f"FT-BATCH-{int(batch.id)}-{int(datetime.utcnow().timestamp())}"
        pi = PaymentIntent(
            user_id=int(u.id),
            provider=provider.name,
            reference=reference,
            purpose="order",
            amount=_minor_to_money(total_minor),
            amount_minor=int(total_minor),
            status=PaymentIntentStatus.INITIALIZED,
            updated_at=datetime.utcnow(),
            meta=json.dumps(
                {
                    "purpose": "order",
                    "order_ids": order_ids,
                    "batch_id": int(batch.id),
                    "initiated_by": int(u.id),
                    "payment_method": payment_method,
                }
            ),
        )
        db.session.add(pi)
        db.session.commit()
        transition_intent(
            pi,
            PaymentIntentStatus.INITIALIZED,
            actor={"type": "user", "id": int(u.id)},
            idempotency_key=f"init:{pi.reference}:initialized",
            reason="payment_initialized_bulk",
            metadata={"order_ids": order_ids, "batch_id": int(batch.id)},
        )
        init_result = provider.initialize(
            order_id=int(order_ids[0]) if order_ids else None,
            amount=_minor_to_money(total_minor),
            email=(u.email or ""),
            reference=pi.reference,
            metadata={
                "order_ids": order_ids,
                "batch_id": int(batch.id),
                "payment_method": payment_method,
            },
        )
        if init_result.reference and init_result.reference != pi.reference:
            pi.reference = init_result.reference
        for order in orders:
            order.payment_reference = pi.reference
            db.session.add(order)
        batch.payment_intent_id = int(pi.id)
        batch.status = "awaiting_payment"
        batch.updated_at = datetime.utcnow()
        db.session.add(batch)
        db.session.add(pi)
        db.session.commit()
        response = {
            "ok": True,
            "mode": "paystack",
            "payment_method": payment_method,
            "batch_id": int(batch.id),
            "payment_intent_id": int(pi.id),
            "order_ids": order_ids,
            "reference": pi.reference,
            "authorization_url": init_result.authorization_url,
            "total_minor": int(total_minor),
            "total": _minor_to_money(total_minor),
            "status": "awaiting_payment",
        }

    try:
        CartItem.query.filter(CartItem.user_id == int(u.id), CartItem.listing_id.in_(listing_ids)).delete(synchronize_session=False)
        db.session.commit()
    except Exception:
        db.session.rollback()

    if idem_row is not None:
        store_response(idem_row, response, 200)
    return jsonify(response), 200


@orders_bp.post("/orders/<int:order_id>/mark-paid")
def mark_paid(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    if not (_is_admin(u) or int(o.buyer_id) == int(u.id)):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    reference = (payload.get("reference") or payload.get("payment_reference") or "").strip()

    try:
        _mark_paid(o, reference if reference else None, actor_id=int(u.id))
        o.updated_at = datetime.utcnow()
        db.session.add(o)
        db.session.commit()
        return jsonify({"ok": True, "order": o.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


def _availability_token_from_request() -> str:
    payload = request.get_json(silent=True) or {}
    token = (payload.get("token") or request.args.get("token") or "").strip()
    return token


def _availability_expire(order: Order, conf: AvailabilityConfirmation) -> None:
    conf.status = "expired"
    conf.responded_at = datetime.utcnow()
    if order:
        order.status = "cancelled"
        order.updated_at = datetime.utcnow()
        if order.listing_id:
            listing = Listing.query.get(int(order.listing_id))
            if listing and hasattr(listing, "is_active"):
                listing.is_active = True
        _refund_escrow(order)
        try:
            transition_escrow(
                order,
                EscrowStatus.REFUNDED,
                idempotency_key=f"availability_expired_refund:{int(order.id)}",
                actor={"type": "system"},
                reason="availability_expired",
            )
        except Exception:
            pass
        _event(int(order.id), None, "availability_expired", "Availability confirmation expired")


@orders_bp.post("/availability/confirm")
def availability_confirm():
    token = _availability_token_from_request()
    if not token:
        return jsonify({"message": "token required"}), 400

    conf = AvailabilityConfirmation.query.filter_by(response_token=token).first()
    if not conf:
        return jsonify({"message": "Not found"}), 404

    if (conf.status or "") != "pending":
        return jsonify({"message": "Already responded"}), 409

    now = datetime.utcnow()
    if conf.deadline_at and now > conf.deadline_at:
        order = Order.query.get(int(conf.order_id))
        _availability_expire(order, conf)
        db.session.commit()
        return jsonify({"message": "Expired"}), 410

    order = Order.query.get(int(conf.order_id))
    if not order:
        return jsonify({"message": "Order not found"}), 404

    listing = Listing.query.get(int(order.listing_id)) if order.listing_id else None
    if listing and hasattr(listing, "is_active") and not bool(getattr(listing, "is_active")):
        conf.status = "no"
        conf.responded_at = now
        order.status = "cancelled"
        order.updated_at = now
        _refund_escrow(order)
        try:
            transition_escrow(
                order,
                EscrowStatus.REFUNDED,
                idempotency_key=f"availability_no_refund:{int(order.id)}",
                actor={"type": "system"},
                reason="listing_unavailable",
            )
        except Exception:
            pass
        _event(int(order.id), None, "availability_no", "Listing already locked")
        db.session.commit()
        return jsonify({"message": "Listing already unavailable"}), 409

    conf.status = "yes"
    conf.responded_at = now
    if listing and hasattr(listing, "is_active"):
        listing.is_active = False
    order.updated_at = now
    _ensure_codes(order)
    _event(int(order.id), None, "availability_yes", "Availability confirmed")

    db.session.add(order)
    db.session.commit()
    return jsonify({"ok": True, "order": order.to_dict(), "availability": conf.to_dict()}), 200


@orders_bp.post("/availability/deny")
def availability_deny():
    token = _availability_token_from_request()
    if not token:
        return jsonify({"message": "token required"}), 400

    conf = AvailabilityConfirmation.query.filter_by(response_token=token).first()
    if not conf:
        return jsonify({"message": "Not found"}), 404

    if (conf.status or "") != "pending":
        return jsonify({"message": "Already responded"}), 409

    now = datetime.utcnow()
    if conf.deadline_at and now > conf.deadline_at:
        order = Order.query.get(int(conf.order_id))
        _availability_expire(order, conf)
        db.session.commit()
        return jsonify({"message": "Expired"}), 410

    order = Order.query.get(int(conf.order_id))
    if not order:
        return jsonify({"message": "Order not found"}), 404

    conf.status = "no"
    conf.responded_at = now
    order.status = "cancelled"
    order.updated_at = now
    if order.listing_id:
        listing = Listing.query.get(int(order.listing_id))
        if listing and hasattr(listing, "is_active"):
            listing.is_active = True

    _refund_escrow(order)
    try:
        transition_escrow(
            order,
            EscrowStatus.REFUNDED,
            idempotency_key=f"availability_deny_refund:{int(order.id)}",
            actor={"type": "system"},
            reason="availability_denied",
        )
    except Exception:
        pass
    _event(int(order.id), None, "availability_no", "Availability denied by seller")

    db.session.add(order)
    db.session.commit()
    return jsonify({"ok": True, "order": order.to_dict(), "availability": conf.to_dict()}), 200


@orders_bp.post("/availability/run-timeouts")
def availability_run_timeouts():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    payload = request.get_json(silent=True) or {}
    try:
        limit = int(payload.get("limit") or 200)
    except Exception:
        limit = 200
    return jsonify(run_availability_timeouts(limit=limit)), 200


@orders_bp.get("/orders/my")
def my_orders():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    rows = Order.query.filter_by(buyer_id=u.id).order_by(Order.created_at.desc()).limit(200).all()
    return jsonify([o.to_dict() for o in rows]), 200


@orders_bp.get("/merchant/orders")
def merchant_orders():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    r = _role(u)
    if r not in ("merchant", "admin"):
        return jsonify([]), 200

    rows = Order.query.filter_by(merchant_id=u.id).order_by(Order.created_at.desc()).limit(200).all()
    return jsonify([o.to_dict() for o in rows]), 200


@orders_bp.get("/orders/<int:order_id>")
def get_order(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    if not (_is_admin(u) or int(u.id) in (int(o.buyer_id), int(o.merchant_id)) or (o.driver_id and int(o.driver_id) == int(u.id))):
        return jsonify({"message": "Forbidden"}), 403

    return jsonify(o.to_dict()), 200


@orders_bp.get("/orders/<int:order_id>/delivery")
def order_delivery(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    try:
        oid = int(order_id)
    except Exception:
        return jsonify({"ok": False, "error": "order_not_found"}), 404

    try:
        db.session.execute(text("SELECT 1"))
        o = db.session.get(Order, oid)
    except Exception as e:
        db.session.rollback()
        try:
            current_app.logger.exception("orders.delivery failed order_id=%s user_id=%s", int(order_id), int(getattr(u, "id", 0) or 0))
        except Exception:
            pass
        detail = None
        try:
            debug_header = (request.headers.get("X-Debug") or "").strip() == "1"
            if _is_admin(u) and debug_header:
                detail = f"{type(e).__name__}: {e}"
        except Exception:
            detail = None
        if detail:
            return jsonify({"ok": False, "error": "db_error", "detail": detail}), 500
        return jsonify({"ok": False, "error": "db_error"}), 500
    if not o:
        return jsonify({"ok": False, "error": "order_not_found"}), 404

    if not (_is_admin(u) or int(u.id) in (int(o.buyer_id), int(o.merchant_id)) or (o.driver_id and int(o.driver_id) == int(u.id))):
        return jsonify({"ok": False, "error": "forbidden"}), 403

    role = (getattr(u, "role", None) or "buyer").strip().lower()
    is_admin = role == "admin"
    is_buyer = int(u.id) == int(o.buyer_id)
    is_merchant = int(u.id) == int(o.merchant_id)
    is_driver = bool(o.driver_id and int(o.driver_id) == int(u.id))

    try:
        pickup_code = o.pickup_code if (is_merchant or is_admin) else None
        dropoff_code = o.dropoff_code if (is_driver or is_admin or is_buyer) else None
        pickup_attempts = int(o.pickup_code_attempts or 0)
        dropoff_attempts = int(o.dropoff_code_attempts or 0)
        max_attempts = 4
        progress = {
            "status": (o.status or ""),
            "pickup_confirmed_at": o.pickup_confirmed_at.isoformat() if o.pickup_confirmed_at else None,
            "dropoff_confirmed_at": o.dropoff_confirmed_at.isoformat() if o.dropoff_confirmed_at else None,
        }
        codes = {
            "pickup_code": pickup_code or None,
            "dropoff_code": dropoff_code or None,
            "pickup_code_attempts": pickup_attempts,
            "dropoff_code_attempts": dropoff_attempts,
            "pickup_attempts_left": max(0, max_attempts - pickup_attempts),
            "dropoff_attempts_left": max(0, max_attempts - dropoff_attempts),
        }
        return jsonify({"ok": True, "order_id": int(o.id), "progress": progress, "codes": codes, "role": role}), 200
    except Exception:
        db.session.rollback()
        try:
            current_app.logger.exception("order_delivery_failed order_id=%s user_id=%s role=%s", int(o.id), int(getattr(u, "id", 0) or 0), role)
        except Exception:
            pass
        return jsonify({"ok": True, "order_id": int(o.id), "progress": {}, "codes": {}, "role": role}), 200


@orders_bp.get("/orders/<int:order_id>/timeline")
def timeline(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    if not (_is_admin(u) or int(u.id) in (int(o.buyer_id), int(o.merchant_id)) or (o.driver_id and int(o.driver_id) == int(u.id))):
        return jsonify({"message": "Forbidden"}), 403

    events = OrderEvent.query.filter_by(order_id=order_id).order_by(OrderEvent.created_at.asc()).all()
    return jsonify({"ok": True, "items": [e.to_dict() for e in events]}), 200


@orders_bp.get("/admin/orders")
def admin_orders():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    try:
        rows = Order.query.order_by(Order.created_at.desc()).limit(50).all()
        items = []
        for o in rows:
            items.append({
                "id": int(o.id),
                "status": o.status,
                "buyer_id": int(o.buyer_id) if o.buyer_id is not None else None,
                "merchant_id": int(o.merchant_id) if o.merchant_id is not None else None,
                "created_at": o.created_at.isoformat() if o.created_at else None,
            })
        return jsonify({"ok": True, "items": items, "seed_endpoint_present": True}), 200
    except Exception:
        db.session.rollback()
        try:
            current_app.logger.exception("admin_orders_list_failed")
        except Exception:
            pass
        return jsonify({"ok": True, "items": [], "seed_endpoint_present": True}), 200


@orders_bp.get("/admin/users")
def admin_users():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    role = (request.args.get("role") or "").strip().lower()
    email = (request.args.get("email") or "").strip().lower()
    try:
        q = User.query
        if email:
            q = q.filter(db.func.lower(User.email) == email)
        if role:
            q = q.filter_by(role=role)
        rows = q.order_by(User.id.desc()).limit(200).all()
        items = []
        for r in rows:
            items.append({
                "id": int(r.id),
                "email": (r.email or ""),
                "name": (r.name or ""),
                "role": (getattr(r, "role", "") or "buyer"),
            })
        return jsonify({"ok": True, "items": items}), 200
    except Exception:
        db.session.rollback()
        try:
            current_app.logger.exception("admin_users_list_failed")
        except Exception:
            pass
        return jsonify({"ok": True, "items": []}), 200


@orders_bp.get("/admin/listings")
def admin_listings():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    q_text = (request.args.get("q") or "").strip()
    state = (request.args.get("state") or "").strip()
    category = (request.args.get("category") or "").strip()
    status = (request.args.get("status") or "").strip().lower()
    sort = (request.args.get("sort") or "newest").strip().lower()
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
    if limit > 200:
        limit = 200
    if offset < 0:
        offset = 0

    try:
        query = Listing.query.outerjoin(User, User.id == Listing.user_id)
        if q_text:
            like = f"%{q_text}%"
            query = query.filter(
                or_(
                    Listing.title.ilike(like),
                    Listing.description.ilike(like),
                    Listing.city.ilike(like),
                    Listing.state.ilike(like),
                    User.email.ilike(like),
                    User.name.ilike(like),
                )
            )
        if state:
            query = query.filter(Listing.state.ilike(state))
        if category:
            query = query.filter(Listing.category.ilike(category))
        if status in ("active", "inactive"):
            query = query.filter(Listing.is_active.is_(status == "active"))

        if sort == "price_asc":
            query = query.order_by(Listing.price.asc(), Listing.id.desc())
        elif sort == "price_desc":
            query = query.order_by(Listing.price.desc(), Listing.id.desc())
        elif sort == "oldest":
            query = query.order_by(Listing.created_at.asc(), Listing.id.asc())
        else:
            query = query.order_by(Listing.created_at.desc(), Listing.id.desc())

        total = query.count()
        rows = query.offset(offset).limit(limit).all()
        merchant_ids = [int(r.user_id) for r in rows if getattr(r, "user_id", None) is not None]
        merchants = User.query.filter(User.id.in_(merchant_ids)).all() if merchant_ids else []
        merchants_by_id = {int(m.id): m for m in merchants}
        items = []
        for r in rows:
            merchant_id = None
            try:
                merchant_id = int(r.user_id) if r.user_id is not None else None
            except Exception:
                merchant_id = None
            merchant = merchants_by_id.get(merchant_id) if merchant_id is not None else None
            items.append({
                "id": int(r.id),
                "title": (r.title or ""),
                "description": (r.description or ""),
                "state": (r.state or ""),
                "city": (r.city or ""),
                "category": (getattr(r, "category", None) or ""),
                "price": float(r.price or 0.0),
                "base_price": float(getattr(r, "base_price", 0.0) or 0.0),
                "platform_fee": float(getattr(r, "platform_fee", 0.0) or 0.0),
                "final_price": float(getattr(r, "final_price", 0.0) or 0.0),
                "is_active": bool(getattr(r, "is_active", True)),
                "status": "active" if bool(getattr(r, "is_active", True)) else "inactive",
                "created_at": r.created_at.isoformat() if getattr(r, "created_at", None) else None,
                "merchant_id": merchant_id,
                "merchant": {
                    "id": merchant_id,
                    "name": (getattr(merchant, "name", "") or "") if merchant else "",
                    "email": (getattr(merchant, "email", "") or "") if merchant else "",
                    "role": (getattr(merchant, "role", "") or "") if merchant else "",
                },
            })
        return jsonify({"ok": True, "items": items, "total": int(total), "limit": int(limit), "offset": int(offset)}), 200
    except Exception:
        db.session.rollback()
        try:
            current_app.logger.exception("admin_listings_list_failed")
        except Exception:
            pass
        return jsonify({"ok": True, "items": [], "total": 0, "limit": int(limit), "offset": int(offset)}), 200


@orders_bp.post("/orders/<int:order_id>/merchant/accept")
def merchant_accept(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    if int(o.merchant_id) != int(u.id) and not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    if not _is_admin(u) and not _is_verified(u):
        return jsonify({"error": "EMAIL_NOT_VERIFIED", "message": "Your email must be verified to perform this action"}), 403

    if not _availability_is_confirmed(int(o.id)):
        return jsonify({"message": "Availability confirmation required"}), 409
    if (o.fulfillment_mode or "unselected") == "unselected":
        return jsonify({"message": "Buyer must choose pickup/delivery/inspection first"}), 409

    o.status = "merchant_accepted"
    o.updated_at = datetime.utcnow()

    # Demo auto-assign driver for demo listings (keeps role checks intact)
    # Skip if already assigned (e.g., smoke test wants a fresh accept).
    try:
        if o.driver_id is None and o.listing_id:
            listing = Listing.query.get(int(o.listing_id))
            if listing:
                title = (listing.title or "")
                desc = (listing.description or "")
                if (title.startswith("Demo Listing #") or ("investor demo" in desc.lower())) and os.getenv("DEMO_AUTO_ASSIGN_DRIVER", "0") == "1":
                    demo_driver = User.query.filter_by(email="driver@fliptrybe.com").first()
                    if demo_driver:
                        o.driver_id = int(demo_driver.id)
                        o.status = "driver_assigned"
                        _issue_pickup_unlock(o)
    except Exception:
        pass

    try:
        db.session.add(o)
        db.session.commit()
        _event(o.id, u.id, "merchant_accepted", "Merchant accepted order")
        _notify_user(int(o.buyer_id), "Order Accepted", f"Merchant accepted your order #{int(o.id)}")
        return jsonify({"ok": True, "order": o.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@orders_bp.post("/orders/<int:order_id>/fulfillment")
def set_fulfillment(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    if not (_is_admin(u) or int(o.buyer_id) == int(u.id)):
        return jsonify({"message": "Forbidden"}), 403

    if not _availability_is_confirmed(int(o.id)):
        return jsonify({"message": "Availability confirmation required"}), 409

    payload = request.get_json(silent=True) or {}
    mode = (payload.get("mode") or "").strip().lower()
    if mode not in ("pickup", "delivery", "inspection"):
        return jsonify({"message": "Invalid mode"}), 400

    o.fulfillment_mode = mode
    if mode == "inspection":
        o.inspection_required = True
        o.release_condition = "INSPECTION_PASS"
    else:
        o.inspection_required = False
        o.release_condition = "BUYER_CONFIRM"

    o.updated_at = datetime.utcnow()

    try:
        db.session.add(o)
        db.session.commit()
        listing = Listing.query.get(int(o.listing_id)) if o.listing_id else None
        reveal = _reveal_for_user(o, u, listing)
        return jsonify({"ok": True, "order": o.to_dict(), "reveal": reveal}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@orders_bp.get("/orders/<int:order_id>/reveal")
def reveal_contacts(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    is_participant = _is_admin(u) or int(u.id) in (int(o.buyer_id), int(o.merchant_id)) or (o.driver_id and int(o.driver_id) == int(u.id)) or (o.inspector_id and int(o.inspector_id) == int(u.id))
    if not is_participant:
        return jsonify({"message": "Forbidden"}), 403

    if not _availability_is_confirmed(int(o.id)):
        return jsonify({"message": "Availability confirmation required"}), 409
    if (o.fulfillment_mode or "unselected") == "unselected":
        return jsonify({"message": "Fulfillment mode not selected"}), 409

    listing = Listing.query.get(int(o.listing_id)) if o.listing_id else None
    reveal = _reveal_for_user(o, u, listing)
    return jsonify({"ok": True, "reveal": reveal}), 200


@orders_bp.post("/orders/<int:order_id>/qr/issue")
def issue_qr(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    payload = request.get_json(silent=True) or {}
    step = (payload.get("step") or "").strip().lower()
    if step not in ("pickup_seller", "delivery_driver", "inspection_inspector"):
        return jsonify({"message": "Invalid step"}), 400

    issuer_role, _ = _qr_roles(step)
    r = _role(u)
    if not _is_admin(u):
        if step == "pickup_seller" and (not o.driver_id or int(o.driver_id) != int(u.id)):
            return jsonify({"message": "Driver required"}), 403
        if step == "delivery_driver" and int(o.buyer_id) != int(u.id):
            return jsonify({"message": "Buyer required"}), 403
        if step == "inspection_inspector" and (not o.inspector_id or int(o.inspector_id) != int(u.id)):
            return jsonify({"message": "Inspector required"}), 403
        if r != issuer_role:
            return jsonify({"message": "Role mismatch"}), 403

    try:
        unlock = ensure_unlock(int(o.id), step)
        if not (unlock.code_hash or "").strip():
            return jsonify({"message": "Code not issued yet"}), 409
        token = issue_qr_token(int(o.id), step, issuer_role)
        db.session.add(unlock)
        db.session.commit()
        return jsonify({"ok": True, "token": token, "step": step}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@orders_bp.post("/orders/<int:order_id>/qr/scan")
def scan_qr(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    payload = request.get_json(silent=True) or {}
    token = (payload.get("token") or "").strip()

    ok, msg, data, row = verify_qr_token(token, int(order_id), step=None)
    if not ok:
        return jsonify({"message": msg}), 400

    step = (data.get("step") or "").strip().lower()
    if step not in ("pickup_seller", "delivery_driver", "inspection_inspector"):
        return jsonify({"message": "Invalid step"}), 400

    issuer_role, scanner_role = _qr_roles(step)
    if (data.get("issued_to_role") or "") != issuer_role:
        return jsonify({"message": "Token role mismatch"}), 400
    r = _role(u)
    if not _is_admin(u):
        if step == "pickup_seller" and int(o.merchant_id) != int(u.id):
            return jsonify({"message": "Seller required"}), 403
        if step == "delivery_driver" and (not o.driver_id or int(o.driver_id) != int(u.id)):
            return jsonify({"message": "Driver required"}), 403
        if step == "inspection_inspector" and int(o.merchant_id) != int(u.id):
            return jsonify({"message": "Seller required"}), 403
        if scanner_role != "seller" and r != scanner_role:
            return jsonify({"message": "Role mismatch"}), 403

    try:
        if row:
            mark_qr_scanned(row, scanned_by_user_id=int(u.id))
        unlock = mark_unlock_qr_verified(int(o.id), step)
        if not unlock:
            return jsonify({"message": "Unlock step not found"}), 409
        db.session.commit()
        return jsonify({"ok": True, "step": step}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@orders_bp.post("/orders/<int:order_id>/driver/assign")
def assign_driver(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    # merchant or admin can assign. Drivers accept via /driver/jobs/<id>/accept
    if int(o.merchant_id) != int(u.id) and not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    if not _is_admin(u) and not _is_verified(u):
        return jsonify({"error": "EMAIL_NOT_VERIFIED", "message": "Your email must be verified to perform this action"}), 403

    payload = request.get_json(silent=True) or {}
    try:
        driver_id = int(payload.get("driver_id"))
    except Exception:
        return jsonify({"message": "driver_id required"}), 400

    o.driver_id = driver_id
    o.status = "driver_assigned"
    o.updated_at = datetime.utcnow()

    try:
        _issue_pickup_unlock(o)
        db.session.add(o)
        db.session.commit()
        _event(o.id, u.id, "driver_assigned", f"Assigned driver {driver_id}")
        _notify_user(int(driver_id), "New Delivery Job", f"You were assigned order #{int(o.id)}")
        return jsonify({"ok": True, "order": o.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@orders_bp.post("/orders/<int:order_id>/driver/status")
def driver_status(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    if not (o.driver_id and int(o.driver_id) == int(u.id)):
        return jsonify({"message": "Forbidden"}), 403

    if not _availability_is_confirmed(int(o.id)):
        return jsonify({"message": "Availability confirmation required"}), 409
    if (o.fulfillment_mode or "unselected") == "inspection":
        return jsonify({"message": "Driver status not applicable for inspection flow"}), 409

    payload = request.get_json(silent=True) or {}
    status = (payload.get("status") or "").strip().lower()

    allowed = ("picked_up", "delivered", "completed")
    if status not in allowed:
        return jsonify({"message": "Invalid status"}), 400

    if status == "picked_up" and not o.pickup_confirmed_at:
        return jsonify({"message": "Pickup code confirmation required"}), 409
    if status in ("delivered", "completed") and not o.dropoff_confirmed_at:
        return jsonify({"message": "Dropoff code confirmation required"}), 409

    o.status = status
    o.updated_at = datetime.utcnow()

    try:
        if status == "picked_up" and (o.fulfillment_mode or "unselected") == "delivery":
            _issue_delivery_unlock(o)
        db.session.add(o)
        db.session.commit()
        _event(o.id, u.id, status, f"Driver set status to {status}")

        # In-app notifications
        if status == "picked_up":
            _notify_user(int(o.buyer_id), "Picked Up", f"Driver picked up your order #{int(o.id)}")
            _notify_user(int(o.merchant_id), "Picked Up", f"Order #{int(o.id)} has been picked up")
        elif status in ("delivered", "completed"):
            _notify_user(int(o.buyer_id), "Delivered", f"Your order #{int(o.id)} was delivered")
            _notify_user(int(o.merchant_id), "Delivered", f"Order #{int(o.id)} was delivered")
            _notify_user(int(o.driver_id or u.id), "Completed", f"Delivery completed for order #{int(o.id)}")

        # Auto-receipts on delivered/completed (idempotent)
        if status in ("delivered", "completed"):
            ref = f"order:{int(o.id)}"
            seller_role = "buyer"
            try:
                seller = User.query.get(int(o.merchant_id))
                seller_role = (getattr(seller, "role", "") or "buyer").strip().lower()
                if seller_role in ("driver", "inspector"):
                    seller_role = "merchant"
            except Exception:
                seller_role = "buyer"
            _receipt_once(
                user_id=int(o.merchant_id),
                kind="listing_sale",
                reference=ref,
                amount=float(o.amount or 0.0),
                description="Listing sale commission",
                meta={"order_id": int(o.id), "role": seller_role},
            )

            # Buyer commission on delivery
            _receipt_once(
                user_id=int(o.buyer_id),
                kind="delivery",
                reference=ref,
                amount=float(o.delivery_fee or 0.0),
                description="Delivery commission",
                meta={"order_id": int(o.id), "role": "buyer"},
            )

        return jsonify({"ok": True, "order": o.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@orders_bp.get("/orders/<int:order_id>/codes")
def get_delivery_codes(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    # Only participants can view codes, and never reveal both to buyer/merchant.
    is_admin = _is_admin(u)
    is_buyer = int(o.buyer_id) == int(u.id)
    is_merchant = int(o.merchant_id) == int(u.id)
    is_driver = (o.driver_id is not None and int(o.driver_id) == int(u.id))

    if not (is_admin or is_buyer or is_merchant or is_driver):
        return jsonify({"message": "Forbidden"}), 403

    if not _availability_is_confirmed(int(o.id)):
        return jsonify({"message": "Availability confirmation required"}), 409
    if (o.fulfillment_mode or "unselected") == "inspection":
        return jsonify({"message": "Codes not used for inspection"}), 409

    return jsonify({"ok": True, "message": "Codes are delivered via SMS and QR. Codes are not retrievable by API."}), 200


def _bump_attempts(o: Order, which: str) -> bool:
    """Returns True if still allowed, False if locked."""
    try:
        if which == "pickup":
            o.pickup_code_attempts = int(o.pickup_code_attempts or 0) + 1
            return int(o.pickup_code_attempts) < 4
        o.dropoff_code_attempts = int(o.dropoff_code_attempts or 0) + 1
        return int(o.dropoff_code_attempts) < 4
    except Exception:
        return False


def _confirm_pickup_unlock(o: Order, u: User, code: str):
    if not (_is_admin(u) or int(o.merchant_id) == int(u.id)):
        return jsonify({"message": "Forbidden"}), 403

    if not _availability_is_confirmed(int(o.id)):
        return jsonify({"message": "Availability confirmation required"}), 409
    if (o.fulfillment_mode or "unselected") == "inspection":
        return jsonify({"message": "Pickup not required for inspection"}), 409
    if not o.driver_id:
        return jsonify({"message": "Driver not assigned"}), 409

    unlock = EscrowUnlock.query.filter_by(order_id=int(o.id), step="pickup_seller").first()
    if not unlock:
        return jsonify({"message": "Pickup unlock not initialized"}), 409
    if unlock.unlocked_at or o.pickup_confirmed_at:
        return jsonify({"message": "Pickup already confirmed"}), 409
    if unlock.locked:
        return jsonify({"message": "Pickup code locked. Contact admin."}), 423
    if unlock.expires_at and datetime.utcnow() > unlock.expires_at:
        return jsonify({"message": "Pickup code expired"}), 409
    if unlock.qr_required and not unlock.qr_verified:
        return jsonify({"message": "QR scan required before pickup confirmation"}), 409

    if not verify_code(unlock, int(o.id), "pickup_seller", code):
        allowed = bump_attempts(unlock)
        try:
            db.session.add(unlock)
            db.session.commit()
        except Exception:
            pass
        if not allowed:
            return jsonify({"message": "Pickup code locked. Contact admin."}), 423
        return jsonify({"message": "Invalid pickup code"}), 400

    unlock.unlocked_at = datetime.utcnow()
    o.pickup_confirmed_at = datetime.utcnow()
    if o.status in ("merchant_accepted", "driver_assigned", "assigned"):
        o.status = "picked_up"
    o.updated_at = datetime.utcnow()

    try:
        release_seller_payout(o)
        try:
            record_event(
                "payout_release",
                user=u,
                context={"order_id": int(o.id), "role": "merchant", "step": "pickup_confirmed"},
                request_id=request.headers.get("X-Request-Id"),
            )
        except Exception:
            pass
        db.session.add(unlock)
        db.session.add(o)
        db.session.commit()
        _event(o.id, u.id, "picked_up", "Pickup confirmed (QR + code)")
        _notify_user(int(o.buyer_id), "Picked Up", f"Driver picked up your order #{int(o.id)}")
        _notify_user(int(o.merchant_id), "Picked Up", f"Order #{int(o.id)} has been picked up")
        return jsonify({"ok": True, "order": o.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


def _confirm_delivery_unlock(o: Order, u: User, code: str):
    if not (_is_admin(u) or (o.driver_id and int(o.driver_id) == int(u.id))):
        return jsonify({"message": "Forbidden"}), 403

    if not _availability_is_confirmed(int(o.id)):
        return jsonify({"message": "Availability confirmation required"}), 409
    if (o.fulfillment_mode or "unselected") == "inspection":
        return jsonify({"message": "Dropoff not required for inspection"}), 409

    unlock = EscrowUnlock.query.filter_by(order_id=int(o.id), step="delivery_driver").first()
    if not unlock:
        return jsonify({"message": "Delivery unlock not initialized"}), 409
    if unlock.unlocked_at or o.dropoff_confirmed_at:
        return jsonify({"message": "Delivery already confirmed"}), 409
    if unlock.locked:
        return jsonify({"message": "Delivery code locked. Contact admin."}), 423
    if unlock.expires_at and datetime.utcnow() > unlock.expires_at:
        return jsonify({"message": "Delivery code expired"}), 409
    if unlock.qr_required and not unlock.qr_verified:
        return jsonify({"message": "QR scan required before delivery confirmation"}), 409

    if not verify_code(unlock, int(o.id), "delivery_driver", code):
        allowed = bump_attempts(unlock)
        try:
            db.session.add(unlock)
            db.session.commit()
        except Exception:
            pass
        if not allowed:
            return jsonify({"message": "Delivery code locked. Contact admin."}), 423
        return jsonify({"message": "Invalid delivery code"}), 400

    unlock.unlocked_at = datetime.utcnow()
    o.dropoff_confirmed_at = datetime.utcnow()
    o.status = "delivered"
    o.updated_at = datetime.utcnow()

    try:
        release_driver_payout(o)
        try:
            record_event(
                "payout_release",
                user=u,
                context={"order_id": int(o.id), "role": "driver", "step": "delivery_confirmed"},
                request_id=request.headers.get("X-Request-Id"),
            )
        except Exception:
            db.session.rollback()
        try:
            transition_escrow(
                o,
                EscrowStatus.RELEASED,
                idempotency_key=f"delivery_release:{int(o.id)}",
                actor={"type": "driver", "id": int(getattr(u, 'id', 0) or 0)},
                reason="delivery_confirmed",
            )
        except Exception:
            db.session.rollback()
        db.session.add(unlock)
        db.session.add(o)
        db.session.commit()
        _event(o.id, u.id, "delivered", "Delivery confirmed (QR + code)")
        _notify_user(int(o.buyer_id), "Delivered", f"Your order #{int(o.id)} was delivered")
        _notify_user(int(o.merchant_id), "Delivered", f"Order #{int(o.id)} was delivered")
        return jsonify({"ok": True, "order": o.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@orders_bp.post("/seller/orders/<int:order_id>/confirm-pickup")
def seller_confirm_pickup(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u) and not _is_verified(u):
        return jsonify({"error": "EMAIL_NOT_VERIFIED", "message": "Your email must be verified to perform this action"}), 403

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    payload = request.get_json(silent=True) or {}
    code = (payload.get("code") or "").strip()
    return _confirm_pickup_unlock(o, u, code)


@orders_bp.post("/driver/orders/<int:order_id>/confirm-delivery")
def driver_confirm_delivery(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    payload = request.get_json(silent=True) or {}
    code = (payload.get("code") or "").strip()
    return _confirm_delivery_unlock(o, u, code)


@orders_bp.post("/orders/<int:order_id>/driver/confirm-pickup")
def driver_confirm_pickup(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    payload = request.get_json(silent=True) or {}
    code = (payload.get("code") or "").strip()
    return _confirm_pickup_unlock(o, u, code)


@orders_bp.post("/orders/<int:order_id>/driver/confirm-dropoff")
def driver_confirm_dropoff(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    payload = request.get_json(silent=True) or {}
    code = (payload.get("code") or "").strip()
    return _confirm_delivery_unlock(o, u, code)


@orders_bp.post("/driver/orders/<int:order_id>/unlock/confirm-code")
def driver_unlock_confirm(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    if not (o.driver_id and int(o.driver_id) == int(u.id)) and not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    unlock = EscrowUnlock.query.filter_by(order_id=int(o.id), step="pickup_seller").first()
    if not unlock:
        return jsonify({"message": "Pickup unlock not initialized"}), 409
    if not unlock.locked:
        return jsonify({"message": "Pickup unlock is not locked"}), 400

    payload = request.get_json(silent=True) or {}
    code = (payload.get("code") or "").strip()
    if not verify_code(unlock, int(o.id), "pickup_seller", code):
        return jsonify({"message": "Invalid pickup code"}), 400

    token = generate_admin_unlock_token()
    unlock.admin_unlock_token_hash = hash_admin_unlock_token(int(o.id), "pickup_seller", token)
    unlock.admin_unlock_expires_at = datetime.utcnow() + timedelta(minutes=15)
    db.session.add(unlock)
    db.session.commit()
    return jsonify({"ok": True, "unlock_token": token, "expires_in": 900}), 200


@orders_bp.post("/admin/orders/<int:order_id>/unlock-pickup")
def admin_unlock_pickup(order_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    unlock = EscrowUnlock.query.filter_by(order_id=int(o.id), step="pickup_seller").first()
    if not unlock:
        return jsonify({"message": "Pickup unlock not initialized"}), 409

    payload = request.get_json(silent=True) or {}
    token = (payload.get("token") or "").strip()
    if not token:
        return jsonify({"message": "token required"}), 400

    if not unlock.admin_unlock_token_hash:
        return jsonify({"message": "No driver proof token"}), 409
    if unlock.admin_unlock_expires_at and datetime.utcnow() > unlock.admin_unlock_expires_at:
        return jsonify({"message": "Driver proof token expired"}), 409

    expected = hash_admin_unlock_token(int(o.id), "pickup_seller", token)
    if not hmac.compare_digest(str(unlock.admin_unlock_token_hash), str(expected)):
        return jsonify({"message": "Invalid driver proof token"}), 400

    unlock.locked = False
    unlock.attempts = 0
    unlock.admin_unlock_token_hash = None
    unlock.admin_unlock_expires_at = None
    db.session.add(unlock)

    try:
        db.session.add(AuditLog(actor_user_id=int(u.id), action="pickup_unlock", target_type="order", target_id=int(o.id), meta="admin_unlocked_pickup"))
    except Exception:
        pass

    db.session.commit()
    return jsonify({"ok": True, "unlock": unlock.to_dict()}), 200
