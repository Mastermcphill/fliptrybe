import uuid
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

    try:
        listing = Listing.query.order_by(Listing.id.asc()).first()
    except Exception:
        db.session.rollback()
        listing = None

    if listing:
        merchant_id = getattr(listing, "owner_id", None) or getattr(listing, "user_id", None)
        return jsonify({"ok": True, "merchant_id": merchant_id, "listing_id": listing.id}), 200

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
        except Exception:
            db.session.rollback()
            try:
                current_app.logger.exception("seed_listing_create_merchant_failed")
            except Exception:
                pass
            return jsonify({"ok": False, "message": "Failed to create merchant"}), 500

    listing = Listing(
        user_id=int(merchant.id),
        owner_id=int(merchant.id),
        title="Seed Listing",
        description="Auto-seeded listing for order creation smoke tests.",
        state="Lagos",
        city="Ikeja",
        price=10000.0,
        base_price=10000.0,
        platform_fee=300.0,
        final_price=10300.0,
        image_path="",
        is_active=True,
        seed_key=uuid.uuid4().hex,
    )
    try:
        db.session.add(listing)
        db.session.commit()
        return jsonify({"ok": True, "merchant_id": int(merchant.id), "listing_id": int(listing.id)}), 201
    except Exception:
        db.session.rollback()
        try:
            current_app.logger.exception("seed_listing_create_listing_failed")
        except Exception:
            pass
        return jsonify({"ok": False, "message": "Failed to create listing"}), 500
