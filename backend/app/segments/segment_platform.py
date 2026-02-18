import json
import os
import uuid
from datetime import datetime, date

from flask import Blueprint, jsonify, request
from sqlalchemy import or_

from app.extensions import db
from app.utils.jwt_utils import decode_token
from app.utils.ng_locations import NIGERIA_LOCATIONS
from app.models import User, Listing, Shortlet, ShortletBooking, Order, OrderEvent, DriverProfile, PaymentIntent, DriverJob
from app.models import InspectorProfile
from app.models.merchant import MerchantProfile, DisabledUser, DisabledListing
from app.models.withdrawals import Withdrawal
from app.models import Wallet, Transaction
from app.jobs.escrow_runner import _hold_order_into_escrow, _release_escrow
from app.utils.bonding import (
    get_or_create_bond,
    refresh_bond_required_for_tier,
    topup_bond,
    reserve_for_inspection,
    required_amount_for_tier,
)

platform_bp = Blueprint("platform_bp", __name__, url_prefix="/api")


# One-time init guard (per process)
_PLATFORM_INIT_DONE = False


@platform_bp.before_app_request
def _ensure_tables_once():
    global _PLATFORM_INIT_DONE
    if _PLATFORM_INIT_DONE:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _PLATFORM_INIT_DONE = True


# ============================
# SHORTLET (MVP WIRED)
# ============================

def _parse_date(value: str | None):
    raw = (value or "").strip()
    if not raw:
        return None
    try:
        return date.fromisoformat(raw)
    except Exception:
        return None


def _shortlet_is_available(shortlet: Shortlet) -> bool:
    try:
        today = date.today()
    except Exception:
        return True

    available_from = getattr(shortlet, "available_from", None)
    available_to = getattr(shortlet, "available_to", None)

    if available_from and today < available_from:
        return False
    if available_to and today > available_to:
        return False
    return True


def _bearer_token() -> str | None:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    return header.replace("Bearer ", "", 1).strip() or None


def _current_user_from_auth() -> User | None:
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


def _shortlet_to_api(shortlet: Shortlet) -> dict:
    return {
        "id": shortlet.id,
        "host_user_id": None,
        "title": shortlet.title,
        "description": shortlet.description or "",
        "state": shortlet.state or "",
        "city": shortlet.city or "",
        "locality": shortlet.locality or "",
        "lga": shortlet.lga or "",
        "nightly_price": float(shortlet.nightly_price or 0.0),
        "base_price": float(getattr(shortlet, "base_price", 0.0) or 0.0),
        "platform_fee": float(getattr(shortlet, "platform_fee", 0.0) or 0.0),
        "final_price": float(getattr(shortlet, "final_price", 0.0) or 0.0),
        "rooms": int(getattr(shortlet, "beds", 0) or 0),
        "bathrooms": int(getattr(shortlet, "baths", 0) or 0),
        "image_url": (shortlet.image_path or ""),
        "is_available": _shortlet_is_available(shortlet),
        "created_at": shortlet.created_at.isoformat() if shortlet.created_at else None,
    }


def _booking_to_api(booking: ShortletBooking) -> dict:
    return {
        "id": booking.id,
        "shortlet_id": booking.shortlet_id,
        "guest_user_id": None,
        "check_in": booking.check_in.isoformat() if booking.check_in else None,
        "check_out": booking.check_out.isoformat() if booking.check_out else None,
        "nights": int(booking.nights or 1),
        "amount": float(getattr(booking, "total_amount", 0.0) or 0.0),
        "status": booking.status or "pending",
        "payment_reference": None,
        "created_at": booking.created_at.isoformat() if booking.created_at else None,
    }


@platform_bp.get("/shortlets")
def list_shortlets():
    state = (request.args.get("state") or "").strip()
    city = (request.args.get("city") or "").strip()
    locality = (request.args.get("locality") or "").strip()

    q = Shortlet.query
    if state:
        q = q.filter(Shortlet.state.ilike(state))
    if city:
        q = q.filter(Shortlet.city.ilike(city))
    if locality:
        q = q.filter(Shortlet.locality.ilike(locality))

    items = q.order_by(Shortlet.created_at.desc()).all()
    return jsonify([_shortlet_to_api(x) for x in items]), 200


@platform_bp.post("/shortlets")
def create_shortlet():
    payload = request.get_json(silent=True) or {}

    title = (payload.get("title") or "").strip()
    if not title:
        return jsonify({"message": "title is required"}), 400

    amenities_raw = payload.get("amenities")
    if isinstance(amenities_raw, list):
        amenities_raw = json.dumps(amenities_raw)

    house_rules_raw = payload.get("house_rules")
    if isinstance(house_rules_raw, list):
        house_rules_raw = json.dumps(house_rules_raw)

    available_from = _parse_date(payload.get("available_from"))
    available_to = _parse_date(payload.get("available_to"))

    try:
        base_price = float(payload.get("nightly_price") or 0.0)
    except Exception:
        base_price = 0.0
    if base_price < 0:
        base_price = 0.0
    platform_fee = round(base_price * 0.03, 2)
    final_price = round(base_price + platform_fee, 2)

    s = Shortlet(
        title=title,
        description=(payload.get("description") or "").strip(),
        state=(payload.get("state") or "").strip(),
        city=(payload.get("city") or "").strip(),
        locality=(payload.get("locality") or "").strip(),
        lga=(payload.get("lga") or "").strip(),
        nightly_price=final_price,
        base_price=base_price,
        platform_fee=platform_fee,
        final_price=final_price,
        cleaning_fee=float(payload.get("cleaning_fee") or 0.0),
        beds=int(payload.get("rooms") or payload.get("beds") or 1),
        baths=int(payload.get("bathrooms") or payload.get("baths") or 1),
        guests=int(payload.get("guests") or 1),
        image_path=(payload.get("image_url") or payload.get("image_path") or "").strip(),
        property_type=(payload.get("property_type") or "").strip(),
        amenities=amenities_raw if isinstance(amenities_raw, str) else None,
        house_rules=house_rules_raw if isinstance(house_rules_raw, str) else None,
        available_from=available_from,
        available_to=available_to,
    )

    try:
        db.session.add(s)
        db.session.commit()
        return jsonify({"ok": True, "shortlet": _shortlet_to_api(s)}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to create shortlet", "error": str(e)}), 500


@platform_bp.post("/shortlets/book")
def book_shortlet():
    payload = request.get_json(silent=True) or {}

    shortlet_id = payload.get("shortlet_id")
    if not shortlet_id:
        return jsonify({"message": "shortlet_id is required"}), 400

    st = Shortlet.query.get(int(shortlet_id))
    if not st:
        return jsonify({"message": "shortlet not found"}), 404

    check_in = _parse_date(payload.get("check_in"))
    check_out = _parse_date(payload.get("check_out"))
    if not check_in or not check_out:
        return jsonify({"message": "check_in and check_out (YYYY-MM-DD) are required"}), 400
    if check_out < check_in:
        return jsonify({"message": "check_out must be on/after check_in"}), 400

    if getattr(st, "available_from", None) and check_in < st.available_from:
        return jsonify({"message": "shortlet not available"}), 400
    if getattr(st, "available_to", None) and check_out > st.available_to:
        return jsonify({"message": "shortlet not available"}), 400

    nights = (check_out - check_in).days
    try:
        nights = int(payload.get("nights") or nights or 1)
    except Exception:
        nights = nights or 1
    nights = max(nights, 1)

    base_price = float(getattr(st, "base_price", 0.0) or 0.0)
    if base_price <= 0.0:
        base_price = float(st.nightly_price or 0.0)
    cleaning_fee = float(getattr(st, "cleaning_fee", 0.0) or 0.0)
    subtotal = (float(base_price) * nights) + cleaning_fee
    platform_fee = round(subtotal * 0.03, 2)
    amount = float(subtotal) + float(platform_fee)

    b = ShortletBooking(
        shortlet_id=st.id,
        guest_name=(payload.get("guest_name") or "").strip() or None,
        guest_phone=(payload.get("guest_phone") or "").strip() or None,
        check_in=check_in,
        check_out=check_out,
        nights=nights,
        total_amount=amount,
        status="pending",
    )

    try:
        db.session.add(b)
        db.session.commit()
        try:
            if platform_fee > 0:
                from app.utils.wallets import post_txn
                from app.models import User as _User
                import os as _os
                raw = (_os.getenv("PLATFORM_USER_ID") or "").strip()
                platform_user_id = int(raw) if raw.isdigit() else 1
                if not raw:
                    try:
                        admin = _User.query.filter_by(role="admin").order_by(_User.id.asc()).first()
                        if admin:
                            platform_user_id = int(admin.id)
                    except Exception:
                        pass
                post_txn(
                    user_id=int(platform_user_id),
                    direction="credit",
                    amount=float(platform_fee),
                    kind="platform_fee",
                    reference=f"shortlet:{int(st.id)}:{int(b.id)}",
                    note="Shortlet platform fee",
                )
        except Exception:
            pass
        return jsonify({"ok": True, "booking": _booking_to_api(b)}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to book shortlet", "error": str(e)}), 500


@platform_bp.get("/shortlets/bookings")
def list_shortlet_bookings():
    q = ShortletBooking.query
    items = q.order_by(ShortletBooking.created_at.desc()).all()
    return jsonify([_booking_to_api(x) for x in items]), 200


# ============================
# CONFIG / COMMISSIONS
# ============================

def _payments_mode() -> str:
    return os.getenv("PAYMENTS_MODE", "mock").lower()

SALES_COMMISSION_RATE = float(os.getenv("SALES_COMMISSION_RATE", "0.05"))       # 5%
DELIVERY_COMMISSION_RATE = float(os.getenv("DELIVERY_COMMISSION_RATE", "0.10")) # 10%
# Withdrawals are free (no platform fee)
WITHDRAWAL_COMMISSION_RATE = 0.0


def _commission(amount: float, rate: float) -> float:
    try:
        a = float(amount)
    except Exception:
        a = 0.0
    if a < 0:
        a = 0.0
    return round(a * rate, 2)


# ============================
# PAYMENTS (DEMO-SAFE)
# ============================
@platform_bp.post("/payments/initiate")
def payments_initiate():
    payload = request.get_json(silent=True) or {}
    amount = float(payload.get("amount") or 0.0)
    purpose = (payload.get("purpose") or "sale").strip().lower()
    listing_id = payload.get("listing_id")
    user_id = payload.get("user_id")

    if not str(user_id).isdigit():
        return jsonify({"message": "user_id is required"}), 400

    meta = {}
    if str(listing_id).isdigit():
        meta["listing_id"] = int(listing_id)

    ref = uuid.uuid4().hex[:20]
    intent = PaymentIntent(
        reference=ref,
        amount=amount,
        purpose=purpose if purpose in {"sale", "delivery", "withdrawal"} else "sale",
        user_id=int(user_id),
        status="initialized",
        provider=_payments_mode(),
        meta=json.dumps(meta) if meta else None,
    )

    db.session.add(intent)
    db.session.commit()

    return jsonify({
        "ok": True,
        "reference": ref,
        "mode": _payments_mode(),
        "status": intent.status,
        "next": "verify",
    }), 201


@platform_bp.post("/payments/verify")
def payments_verify():
    payload = request.get_json(silent=True) or {}
    ref = (payload.get("reference") or "").strip()
    if not ref:
        return jsonify({"message": "reference is required"}), 400

    intent = PaymentIntent.query.filter_by(reference=ref).first()
    if not intent:
        return jsonify({"message": "Payment intent not found"}), 404

    # Demo-safe: in mock mode, verification always succeeds
    mode = _payments_mode()
    intent.status = "paid"
    intent.provider = mode
    try:
        intent.paid_at = datetime.utcnow()
    except Exception:
        pass

    # Commission calculation
    sale_commission = _commission(intent.amount, SALES_COMMISSION_RATE) if intent.purpose == "sale" else 0.0
    delivery_commission = _commission(intent.amount, DELIVERY_COMMISSION_RATE) if intent.purpose == "delivery" else 0.0
    withdrawal_commission = _commission(intent.amount, WITHDRAWAL_COMMISSION_RATE) if intent.purpose == "withdrawal" else 0.0

    total_commission = round(sale_commission + delivery_commission + withdrawal_commission, 2)
    net = round(float(intent.amount or 0.0) - total_commission, 2)

    # Write a transaction record (best-effort)
    try:
        if intent.user_id:
            wallet = Wallet.query.filter_by(user_id=int(intent.user_id)).first()
            if not wallet:
                wallet = Wallet(user_id=int(intent.user_id), balance=0.0)
                db.session.add(wallet)
                db.session.flush()

            # If it's a withdrawal intent, don't credit wallet. Otherwise credit net.
            if intent.purpose != "withdrawal":
                wallet.balance = float(wallet.balance or 0.0) + net

            tx = Transaction(
                wallet_id=wallet.id,
                amount=float(intent.amount or 0.0),
                gross_amount=float(intent.amount or 0.0),
                net_amount=net if intent.purpose != "withdrawal" else 0.0,
                commission_total=total_commission,
                purpose=intent.purpose,
                direction="credit" if intent.purpose != "withdrawal" else "debit",
                reference=intent.reference,
            )
            db.session.add(tx)
    except Exception:
        pass

    db.session.commit()

    return jsonify({
        "ok": True,
        "reference": intent.reference,
        "status": intent.status,
        "purpose": intent.purpose,
        "amount": float(intent.amount or 0.0),
        "commissions": {
            "sale": sale_commission,
            "delivery": delivery_commission,
            "withdrawal": withdrawal_commission,
            "total": total_commission,
        },
        "net_amount": net,
        "mode": mode,
    }), 200


@platform_bp.post("/withdrawals/request")
def withdrawals_request():
    payload = request.get_json(silent=True) or {}
    user_id = payload.get("user_id")
    amount = float(payload.get("amount") or 0.0)
    destination = (payload.get("destination") or "").strip()

    if not str(user_id).isdigit():
        return jsonify({"message": "user_id is required"}), 400
    if amount <= 0:
        return jsonify({"message": "amount must be > 0"}), 400
    if not destination:
        return jsonify({"message": "destination is required"}), 400

    ref = uuid.uuid4().hex[:24]
    wdr = Withdrawal(
        user_id=int(user_id),
        amount=amount,
        destination=destination,
        reference=ref,
        status="pending",
    )
    db.session.add(wdr)
    db.session.commit()

    return jsonify({"ok": True, "reference": ref, "status": "pending"}), 201


# ============================
# MERCHANT DASHBOARD
# ============================

def _ensure_merchant_profile(user_id: int) -> MerchantProfile:
    mp = MerchantProfile.query.filter_by(user_id=user_id).first()
    if not mp:
        mp = MerchantProfile(user_id=user_id, tier="Starter", score=0.0, is_verified=False)
        db.session.add(mp)
        db.session.commit()
    return mp


@platform_bp.get("/merchant/dashboard")
def merchant_dashboard():
    user_id = request.args.get("user_id")
    if not str(user_id).isdigit():
        return jsonify({"message": "user_id is required"}), 400

    uid = int(user_id)
    mp = _ensure_merchant_profile(uid)

    listings_count = Listing.query.count()
    # Placeholder until full merchant order analytics are wired.
    orders_count = 0
    revenue = 0.0

    return jsonify({
        "ok": True,
        "merchant": mp.to_dict(),
        "stats": {
            "listings_count": listings_count,
            "orders_count": orders_count,
            "revenue": revenue,
        }
    }), 200


# ============================
# ADMIN (MVP SKELETON)
# ============================

@platform_bp.get("/admin/overview")
def admin_overview():
    return jsonify({
        "ok": True,
        "counts": {
            "users": User.query.count(),
            "listings": Listing.query.count(),
        }
    }), 200


@platform_bp.post("/admin/users/<int:user_id>/disable")
def admin_disable_user(user_id: int):
    payload = request.get_json(silent=True) or {}
    reason = (payload.get("reason") or "disabled by admin").strip()

    row = DisabledUser.query.filter_by(user_id=user_id).first()
    if not row:
        row = DisabledUser(user_id=user_id, reason=reason, disabled=True)
        db.session.add(row)
    else:
        row.disabled = True
        row.reason = reason
    db.session.commit()
    try:
        from app.models import MoneyBoxAccount
        from app.utils.moneybox import liquidate_to_wallet
        acct = MoneyBoxAccount.query.filter_by(user_id=int(user_id)).first()
        if acct:
            liquidate_to_wallet(acct, reason="admin_disabled_user", reference=f"disable:{int(user_id)}")
    except Exception:
        pass
    return jsonify({"ok": True, "user_id": user_id, "disabled": True}), 200


@platform_bp.post("/admin/listings/<int:listing_id>/disable")
def admin_disable_listing(listing_id: int):
    payload = request.get_json(silent=True) or {}
    reason = (payload.get("reason") or "disabled by admin").strip()

    row = DisabledListing.query.filter_by(listing_id=listing_id).first()
    if not row:
        row = DisabledListing(listing_id=listing_id, reason=reason, disabled=True)
        db.session.add(row)
    else:
        row.disabled = True
        row.reason = reason
    db.session.commit()
    return jsonify({"ok": True, "listing_id": listing_id, "disabled": True}), 200


# ============================
# ORDERS (MVP)
# ============================

@platform_bp.post("/orders/create")
def orders_create():
    payload = request.get_json(silent=True) or {}
    buyer_id = payload.get("buyer_id")
    listing_id = payload.get("listing_id")

    if not str(buyer_id).isdigit():
        return jsonify({"message": "buyer_id is required"}), 400
    if not str(listing_id).isdigit():
        return jsonify({"message": "listing_id is required"}), 400

    listing = Listing.query.get(int(listing_id))
    if not listing:
        return jsonify({"message": "listing not found"}), 404
    merchant_id = None
    try:
        if listing.user_id:
            merchant_id = int(listing.user_id)
    except Exception:
        merchant_id = None
    if merchant_id is None:
        return jsonify({"message": "listing has no merchant"}), 400

    payment_reference = (payload.get("payment_reference") or payload.get("reference") or "").strip()
    raw_inspection = payload.get("inspection_required")
    inspection_required = False
    if isinstance(raw_inspection, bool):
        inspection_required = raw_inspection
    elif isinstance(raw_inspection, (int, float)):
        inspection_required = int(raw_inspection) == 1
    elif isinstance(raw_inspection, str):
        inspection_required = raw_inspection.strip().lower() in ("1", "true", "yes", "y")

    seller_role = "buyer"
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
        if base_price <= 0.0:
            base_price = float(getattr(listing, "price", 0.0) or 0.0)
        if platform_fee <= 0.0:
            platform_fee = round(base_price * 0.03, 2)
        if final_price <= 0.0:
            final_price = round(base_price + platform_fee, 2)
        amount = float(final_price)
    else:
        amount = float(base_price)

    order = Order(
        buyer_id=int(buyer_id),
        merchant_id=merchant_id,
        listing_id=int(listing_id),
        amount=amount,
        status="created",
        payment_reference=payment_reference if payment_reference else None,
        inspection_required=inspection_required,
    )
    db.session.add(order)
    db.session.commit()

    if payment_reference:
        try:
            order.status = "paid"
            if inspection_required:
                order.release_condition = "INSPECTION_PASS"
            else:
                order.release_condition = "BUYER_CONFIRM"
            _hold_order_into_escrow(order)
            if not inspection_required:
                _release_escrow(order)
            db.session.add(order)
            db.session.commit()
        except Exception:
            db.session.rollback()

    return jsonify({"ok": True, "order": order.to_dict()}), 201


@platform_bp.get("/orders/my")
def orders_my():
    buyer_id = request.args.get("buyer_id")
    if not str(buyer_id).isdigit():
        return jsonify({"message": "buyer_id is required"}), 400

    items = Order.query.filter_by(buyer_id=int(buyer_id)).order_by(Order.created_at.desc()).all()
    return jsonify([x.to_dict() for x in items]), 200


@platform_bp.post("/orders/<int:order_id>/mark-paid")
def orders_mark_paid(order_id: int):
    payload = request.get_json(silent=True) or {}
    reference = (payload.get("reference") or "").strip()

    order = Order.query.get(order_id)
    if not order:
        return jsonify({"message": "order not found"}), 404

    order.status = "paid"
    if reference:
        order.payment_reference = reference

    if order.inspection_required:
        order.release_condition = "INSPECTION_PASS"
    else:
        order.release_condition = "BUYER_CONFIRM"

    try:
        _hold_order_into_escrow(order)
        if not order.inspection_required:
            _release_escrow(order)
    except Exception:
        pass

    # create a driver job skeleton (optional)
    try:
        job = DriverJob(
            order_id=order.id,
            pickup="Seller pickup address",
            dropoff="Buyer dropoff address",
            price=1500.0,
            status="open",
        )
        db.session.add(job)
    except Exception:
        pass

    db.session.commit()
    return jsonify({"ok": True, "order": order.to_dict()}), 200
