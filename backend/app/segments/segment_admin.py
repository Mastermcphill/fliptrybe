import uuid
import inspect
import re
from datetime import datetime, timezone
from sqlalchemy import String, Text, Integer, Float, Numeric, Boolean, DateTime, Enum
from flask import Blueprint, jsonify, request, current_app
from app.extensions import db
from app.models.user import User
from app.models.listing import Listing
from app.utils.jwt_utils import decode_token, get_bearer_token

admin_bp = Blueprint("admin_bp", __name__, url_prefix="/api/admin")

def _current_user():
    header = request.headers.get("Authorization", "")
    token = get_bearer_token(header)
    if not token and header.lower().startswith("token "):
        token = header.replace("Token ", "", 1).strip()
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
        try:
            return db.session.get(User, uid)
        except Exception:
            return None

def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    if (getattr(u, "role", "") or "").strip().lower() == "admin":
        return True
    try:
        return int(u.id or 0) == 1
    except Exception:
        return False

def _debug_detail(e, u):
    try:
        if request.headers.get("X-Debug", "").strip() == "1" and _is_admin(u):
            return f"{type(e).__name__}: {e}"
    except Exception:
        pass
    return None


def _debug_error_payload(e, u):
    detail = _debug_detail(e, u)
    if not detail:
        return None
    out = {
        "detail": detail,
        "exception_type": type(e).__name__,
    }
    try:
        msg = str(e) or ""
        # Helps pinpoint NOT NULL/UndefinedColumn quickly in debug responses.
        m = re.search(r'column "?([a-zA-Z0-9_]+)"?', msg)
        if m:
            out["column"] = m.group(1)
    except Exception:
        pass
    return out


@admin_bp.get("/summary")
def admin_summary():
    return jsonify({
        "ok": True,
        "stats": {
            "users": User.query.count(),
            "listings": Listing.query.count(),
            "orders": 0,
            "reports": 0,
        }
    }), 200


@admin_bp.post("/listings/<int:listing_id>/disable")
def disable_listing(listing_id: int):
    # Placeholder without soft-delete column. For demo, just confirms action.
    return jsonify({"ok": True, "listing_id": listing_id, "action": "disabled"}), 200


@admin_bp.post("/users/<int:user_id>/disable")
def disable_user(user_id: int):
    return jsonify({"ok": True, "user_id": user_id, "action": "disabled"}), 200


@admin_bp.post("/demo/seed-listing")
def seed_listing():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    target_merchant_raw = payload.get("merchant_id")
    if target_merchant_raw is None:
        target_merchant_raw = payload.get("user_id")

    target_merchant_id = None
    if target_merchant_raw is not None:
        try:
            target_merchant_id = int(target_merchant_raw)
        except Exception:
            return jsonify({"ok": False, "error": "invalid_merchant_id"}), 400

    target_merchant = None
    if target_merchant_id is not None:
        try:
            target_merchant = db.session.get(User, int(target_merchant_id))
        except Exception:
            db.session.rollback()
            target_merchant = None
        if not target_merchant:
            return jsonify({"ok": False, "error": "merchant_not_found"}), 404

    try:
        if target_merchant_id is not None:
            listing = Listing.query.filter_by(user_id=int(target_merchant_id)).order_by(Listing.id.asc()).first()
        else:
            listing = Listing.query.order_by(Listing.id.asc()).first()
    except Exception:
        db.session.rollback()
        listing = None

    if listing:
        merchant_id = getattr(listing, "user_id", None)
        if request.headers.get("X-Debug", "").strip() == "1" and _is_admin(u):
            return jsonify({
                "ok": True,
                "merchant_id": merchant_id,
                "listing_id": listing.id,
                "listing": listing.to_dict(),
                "listing_module": getattr(Listing, "__module__", None),
                "listing_file": inspect.getfile(Listing),
            }), 200
        return jsonify({"ok": True, "merchant_id": merchant_id, "listing_id": listing.id}), 200

    merchant = target_merchant
    if not merchant:
        try:
            merchant = User.query.filter_by(role="merchant").order_by(User.id.asc()).first()
        except Exception:
            db.session.rollback()
            merchant = None

    if not merchant:
        email = "merchant@fliptrybe.com"
        try:
            exists = User.query.filter_by(email=email).first()
        except Exception:
            db.session.rollback()
            exists = None
        if exists:
            email = f"merchant_seed_{uuid.uuid4().hex[:8]}@t.com"
        phone = f"+234801{str(uuid.uuid4().int % 10000000).zfill(7)}"
        merchant = User(
            name="Seed Merchant",
            email=email,
            phone=phone,
            role="merchant",
            is_verified=True,
            kyc_tier=1,
            is_available=True,
        )
        merchant.set_password("TempPass123!")
        try:
            db.session.add(merchant)
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            try:
                current_app.logger.exception("seed_listing_create_merchant_failed")
            except Exception:
                pass
            debug_payload = _debug_error_payload(e, u)
            if debug_payload:
                return jsonify({"ok": False, "error": "db_error", **debug_payload}), 500
            return jsonify({"ok": False, "error": "db_error"}), 500

    listing = Listing(
        user_id=int(merchant.id),
        title="Seed Listing",
        description="Auto-seeded listing for order creation smoke tests.",
        state="Lagos",
        city="Ikeja",
        locality="",
        category="declutter",
        price=10000.0,
        base_price=10000.0,
        platform_fee=300.0,
        final_price=10300.0,
        image_path="",
        image_filename="seed.jpg",
        is_active=True,
        created_at=datetime.utcnow(),
        date_posted=datetime.utcnow(),
        seed_key=uuid.uuid4().hex,
    )
    # Seed safety: fill any NOT NULL columns that are still None.
    try:
        for col in Listing.__table__.columns:
            if col.primary_key:
                continue
            if col.nullable:
                continue
            key = col.name
            try:
                val = getattr(listing, key, None)
            except Exception:
                val = None
            if val is not None:
                continue
            ctype = col.type
            try:
                if isinstance(ctype, (String, Text)):
                    setattr(listing, key, "")
                elif isinstance(ctype, (Integer, Float, Numeric)):
                    setattr(listing, key, 0)
                elif isinstance(ctype, Boolean):
                    setattr(listing, key, True)
                elif isinstance(ctype, DateTime):
                    setattr(listing, key, datetime.now(timezone.utc))
                elif isinstance(ctype, Enum) and getattr(ctype, "enums", None):
                    setattr(listing, key, ctype.enums[0])
            except Exception:
                pass
    except Exception:
        pass
    try:
        db.session.add(listing)
        db.session.commit()
        if request.headers.get("X-Debug", "").strip() == "1" and _is_admin(u):
            return jsonify({
                "ok": True,
                "merchant_id": int(merchant.id),
                "listing_id": int(listing.id),
                "category": getattr(listing, "category", None),
                "price": getattr(listing, "price", None),
                "listing": listing.to_dict(),
                "listing_module": getattr(Listing, "__module__", None),
                "listing_file": inspect.getfile(Listing),
            }), 201
        return jsonify({"ok": True, "merchant_id": int(merchant.id), "listing_id": int(listing.id)}), 201
    except Exception as e:
        db.session.rollback()
        try:
            current_app.logger.exception("seed_listing_create_listing_failed")
        except Exception:
            pass
        debug_payload = _debug_error_payload(e, u)
        if debug_payload:
            return jsonify({"ok": False, "error": "db_error", **debug_payload}), 500
        return jsonify({"ok": False, "error": "db_error"}), 500
