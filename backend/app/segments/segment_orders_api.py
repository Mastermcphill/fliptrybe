from __future__ import annotations

import os
import hmac
import random
import secrets
import uuid
from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request, current_app
from sqlalchemy import text

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
    try:
        if int(u.id or 0) == 1:
            return True
    except Exception:
        pass
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
    db.session.commit()
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
    # Do NOT release escrow at payment. Availability + secret-code confirmations gate release.

    try:
        listing = Listing.query.get(int(order.listing_id)) if order.listing_id else None
    except Exception:
        listing = None
    seller_id = None
    if listing:
        try:
            seller_id = int(getattr(listing, "owner_id") or getattr(listing, "user_id") or 0) or None
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


@orders_bp.post("/orders")
def create_order():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    payload = request.get_json(silent=True) or {}

    buyer_id_raw = payload.get("buyer_id")
    try:
        buyer_id = int(buyer_id_raw or u.id)
    except Exception:
        buyer_id = int(u.id)

    if _is_admin(u) and not buyer_id_raw:
        return jsonify({"ok": False, "message": "buyer_id required for admin"}), 400

    if buyer_id != int(u.id) and not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    try:
        merchant_id = int(payload.get("merchant_id"))
    except Exception:
        return jsonify({"ok": False, "message": "merchant_id required"}), 400

    listing_id = payload.get("listing_id")
    try:
        listing_id_int = int(listing_id) if listing_id is not None else None
    except Exception:
        listing_id_int = None
    if listing_id_int is None:
        return jsonify({"ok": False, "message": "listing_id required"}), 400

    try:
        amount = float(payload.get("amount") or 0.0)
    except Exception:
        amount = 0.0

    try:
        delivery_fee = float(payload.get("delivery_fee") or 0.0)
    except Exception:
        delivery_fee = 0.0
    try:
        inspection_fee = float(payload.get("inspection_fee") or 0.0)
    except Exception:
        inspection_fee = 0.0

    pickup = (payload.get("pickup") or "").strip()
    dropoff = (payload.get("dropoff") or "").strip()
    payment_reference = (payload.get("payment_reference") or "").strip()
    inspection_required = _parse_bool(payload.get("inspection_required"))

    # Idempotency: same payment reference + same buyer/merchant returns existing order.
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
            return jsonify({"message": "payment_reference already used"}), 409

    # If listing_id is supplied, align merchant if listing exists and has owner.
    listing = Listing.query.get(listing_id_int) if listing_id_int else None
    if listing_id_int and not listing:
        return jsonify({"ok": False, "message": "listing not found"}), 404
    if listing:
        if listing and getattr(listing, "owner_id", None):
            try:
                merchant_id = int(getattr(listing, "owner_id"))
            except Exception:
                pass
        if listing and hasattr(listing, "is_active") and not bool(getattr(listing, "is_active")):
            return jsonify({"message": "Listing is no longer available"}), 409

    # Seller cannot buy their own listing
    try:
        if int(buyer_id) == int(merchant_id) and not _is_admin(u):
            return jsonify({"message": "Sellers cannot buy their own listings"}), 409
    except Exception:
        pass

# If listing provided, prefer listing pricing rules over payload amount
    if listing:
        try:
            seller = User.query.get(int(merchant_id))
            seller_role = (getattr(seller, "role", "") or "buyer").strip().lower()
            if seller_role in ("driver", "inspector"):
                seller_role = "merchant"
        except Exception:
            seller_role = "buyer"

        base_price = float(getattr(listing, "base_price", 0.0) or 0.0)
        if base_price <= 0.0:
            base_price = float(getattr(listing, "price", 0.0) or 0.0)
        platform_fee = float(getattr(listing, "platform_fee", 0.0) or 0.0)
        final_price = float(getattr(listing, "final_price", 0.0) or 0.0)

        if seller_role == "merchant":
            if platform_fee <= 0.0:
                platform_fee = round(base_price * 0.03, 2)
            if final_price <= 0.0:
                final_price = round(base_price + platform_fee, 2)
            amount = float(final_price)
        else:
            amount = float(base_price)

    handshake_id = (payload.get("handshake_id") or "").strip()
    if not handshake_id:
        handshake_id = str(uuid.uuid4())

    order = Order(
        buyer_id=buyer_id,
        merchant_id=merchant_id,
        listing_id=listing_id_int,
        amount=amount,
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
            _mark_paid(order, payment_reference, actor_id=int(u.id))
            order.updated_at = datetime.utcnow()
            db.session.add(order)
            db.session.commit()
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
        debug_requested = (request.headers.get("X-Debug", "").strip() == "1")
        if debug_requested and _is_admin(u):
            detail = f"{type(e).__name__}: {e}"
            return jsonify({"ok": False, "error": "db_error", "detail": detail}), 500
        return jsonify({"ok": False, "error": "db_error"}), 500


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
    is_admin = role == "admin" or int(getattr(u, "id", 0) or 0) == 1
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

    try:
        rows = Listing.query.order_by(Listing.created_at.desc()).limit(200).all()
        items = []
        for r in rows:
            merchant_id = None
            try:
                merchant_id = int(r.owner_id) if r.owner_id is not None else int(r.user_id) if r.user_id is not None else None
            except Exception:
                merchant_id = None
            items.append({
                "id": int(r.id),
                "merchant_id": merchant_id,
            })
        return jsonify({"ok": True, "items": items}), 200
    except Exception:
        db.session.rollback()
        try:
            current_app.logger.exception("admin_listings_list_failed")
        except Exception:
            pass
        return jsonify({"ok": True, "items": []}), 200


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
        return jsonify({"error": "email_not_verified", "message": "Email verification required to continue."}), 403

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
        return jsonify({"error": "email_not_verified", "message": "Email verification required to continue."}), 403

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
            db.session.rollback()
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
            db.session.rollback()
        if not allowed:
            return jsonify({"message": "Delivery code locked. Contact admin."}), 423
        return jsonify({"message": "Invalid delivery code"}), 400

    unlock.unlocked_at = datetime.utcnow()
    o.dropoff_confirmed_at = datetime.utcnow()
    o.status = "delivered"
    o.updated_at = datetime.utcnow()

    try:
        release_driver_payout(o)
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
        return jsonify({"error": "email_not_verified", "message": "Email verification required to continue."}), 403

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
