from __future__ import annotations

import os
from datetime import datetime

from sqlalchemy import text, or_
from flask import Blueprint, jsonify, request, send_from_directory
from werkzeug.utils import secure_filename

from app.extensions import db
from app.utils.ng_locations import NIGERIA_LOCATIONS
from app.models import User
from app.models import Listing
from app.utils.commission import compute_commission, RATES
from app.utils.listing_caps import enforce_listing_cap
from app.utils.jwt_utils import decode_token, get_bearer_token


market_bp = Blueprint("market_bp", __name__, url_prefix="/api")

# One-time init guard (per process)
_MARKET_INIT_DONE = False

# Upload folder: backend/uploads (stable path)
# This file is: backend/app/segments/segment_market.py
# Go up 3 levels -> backend/
BACKEND_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
UPLOAD_DIR = os.path.join(BACKEND_ROOT, "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

ALLOWED_EXT = {"jpg", "jpeg", "png", "webp"}


@market_bp.before_app_request
def _ensure_tables_once():
    global _MARKET_INIT_DONE
    if _MARKET_INIT_DONE:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _MARKET_INIT_DONE = True


def _base_url() -> str:
    # request.host_url includes trailing slash
    return request.host_url.rstrip("/")


def _is_allowed(filename: str) -> bool:
    if not filename or "." not in filename:
        return False
    ext = filename.rsplit(".", 1)[-1].lower()
    return ext in ALLOWED_EXT



def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    # Earth radius km
    r = 6371.0
    from math import radians, sin, cos, sqrt, atan2
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return r * c





def _apply_listing_active_filter(q):
    try:
        if hasattr(Listing, "is_active"):
            return q.filter(getattr(Listing, "is_active").is_(True))
        if hasattr(Listing, "disabled"):
            return q.filter(getattr(Listing, "disabled").is_(False))
        if hasattr(Listing, "is_disabled"):
            return q.filter(getattr(Listing, "is_disabled").is_(False))
        if hasattr(Listing, "status"):
            return q.filter(db.func.lower(getattr(Listing, "status")) != "disabled")
    except Exception:
        return q
    return q

def _apply_listing_ordering(q):
    try:
        if hasattr(Listing, "created_at"):
            return q.order_by(Listing.created_at.desc())
    except Exception:
        pass
    return q.order_by(Listing.id.desc())

def _bearer_token() -> str | None:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    return header.replace("Bearer ", "", 1).strip() or None


def _current_user():
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

def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    role = (getattr(u, "role", "") or "").strip().lower()
    if role == "admin":
        return True
    try:
        if "admin" in (u.email or "").lower():
            return True
    except Exception:
        pass
    try:
        return int(u.id or 0) == 1
    except Exception:
        return False

def _is_owner(u: User | None, listing: Listing) -> bool:
    if not u:
        return False
    try:
        if listing.owner_id and int(listing.owner_id) == int(u.id):
            return True
    except Exception:
        pass
    try:
        if listing.user_id and int(listing.user_id) == int(u.id):
            return True
    except Exception:
        pass
    return False


def _is_email_verified(u: User | None) -> bool:
    if not u:
        return False
    return bool(getattr(u, "is_verified", False))


def _is_active_listing(listing: Listing) -> bool:
    try:
        if hasattr(listing, "is_active"):
            return bool(getattr(listing, "is_active"))
        if hasattr(listing, "disabled"):
            return not bool(getattr(listing, "disabled"))
        if hasattr(listing, "is_disabled"):
            return not bool(getattr(listing, "is_disabled"))
        if hasattr(listing, "status"):
            return (str(getattr(listing, "status") or "").strip().lower() not in ("disabled", "inactive"))
    except Exception:
        pass
    return True


def _seller_role(user_id: int | None) -> str:
    if not user_id:
        return "guest"
    try:
        u = User.query.get(int(user_id))
    except Exception:
        u = None
    if not u:
        return "guest"
    role = (getattr(u, "role", None) or "buyer").strip().lower()
    if role in ("driver", "inspector"):
        return "merchant"
    return role


def _account_role(user_id: int | None) -> str:
    if not user_id:
        return "buyer"
    try:
        u = User.query.get(int(user_id))
    except Exception:
        u = None
    if not u:
        return "buyer"
    return (getattr(u, "role", None) or "buyer").strip().lower()


def _apply_pricing_for_listing(listing: Listing, *, base_price: float, seller_role: str) -> None:
    try:
        base = float(base_price or 0.0)
    except Exception:
        base = 0.0
    if base < 0:
        base = 0.0
    platform_fee = 0.0
    final_price = base
    if seller_role == "merchant":
        platform_fee = round(base * 0.03, 2)
        final_price = round(base + platform_fee, 2)

    try:
        listing.base_price = float(base)
        listing.platform_fee = float(platform_fee)
        listing.final_price = float(final_price)
    except Exception:
        pass
    listing.price = float(final_price)

@market_bp.get("/locations/popular")
def popular_locations():
    """Top locations by listing count. Used for investor demo and quick filters."""
    try:
        rows = db.session.execute(text("""
            SELECT state, city, COUNT(*) AS c
            FROM listings
            WHERE state IS NOT NULL AND TRIM(state) != ''
            GROUP BY state, city
            ORDER BY c DESC
            LIMIT 50
        """)).fetchall()
        items = []
        for r in rows:
            items.append({
                "state": (r[0] or "").strip(),
                "city": (r[1] or "").strip(),
                "count": int(r[2] or 0),
            })
        return jsonify({"ok": True, "items": items}), 200
    except Exception:
        return jsonify({"ok": True, "items": []}), 200


@market_bp.get("/locations")
def locations_compat():
    """Compatibility endpoint for frontend location pickers.
    Returns a Nigeria-wide catalog: {ok:true, items:[{state, cities[]}, ...]}
    """
    return jsonify({"ok": True, "items": NIGERIA_LOCATIONS}), 200


@market_bp.get("/heatmap")
def heatmap_compat():
    """Simple heatmap data (investor demo).
    Returns [{state, city, count}] in an 'items' wrapper.
    """
    try:
        rows = db.session.execute(text("""
            SELECT state, city, COUNT(*) AS c
            FROM listings
            WHERE state IS NOT NULL AND TRIM(state) != ''
            GROUP BY state, city
            ORDER BY c DESC
            LIMIT 200
        """)).fetchall()
        items = []
        for r in rows:
            items.append({
                "state": (r[0] or "").strip(),
                "city": (r[1] or "").strip(),
                "count": int(r[2] or 0),
            })
        return jsonify({"ok": True, "items": items}), 200
    except Exception:
        return jsonify({"ok": True, "items": []}), 200


@market_bp.get("/heat")
def heat():
    """Heat buckets for simple 'map-like' demo (state/city counts)."""
    try:
        rows = db.session.execute(text("""
            SELECT state, city, COUNT(*) AS c
            FROM listings
            WHERE state IS NOT NULL AND TRIM(state) != ''
            GROUP BY state, city
            ORDER BY c DESC
        """)).fetchall()
        buckets = []
        for r in rows:
            buckets.append({
                "state": (r[0] or "").strip(),
                "city": (r[1] or "").strip(),
                "count": int(r[2] or 0),
            })
        return jsonify({"ok": True, "buckets": buckets}), 200
    except Exception:
        return jsonify({"ok": True, "buckets": []}), 200


@market_bp.get("/fees/quote")
def fees_quote():
    """Quick fee quote endpoint for investor/demo UI."""
    kind = (request.args.get("kind") or "").strip()  # listing_sale, delivery, withdrawal, shortlet_booking
    raw_amount = (request.args.get("amount") or "").strip()
    try:
        amount = float(raw_amount) if raw_amount else 0.0
    except Exception:
        amount = 0.0

    rate = float(RATES.get(kind, 0.0))
    fee = compute_commission(amount, rate)
    return jsonify({"ok": True, "kind": kind, "amount": amount, "rate": rate, "fee": fee, "total": float(amount) + float(fee)}), 200


@market_bp.post("/listings/price-preview")
def listing_price_preview():
    payload = request.get_json(silent=True) or {}
    raw_base = payload.get("base_price")
    listing_type = (payload.get("listing_type") or "declutter").strip().lower()
    seller_role = (payload.get("seller_role") or "buyer").strip().lower()

    try:
        base_price = float(raw_base or 0.0)
    except Exception:
        base_price = 0.0
    if base_price < 0:
        base_price = 0.0

    if seller_role in ("driver", "inspector"):
        seller_role = "merchant"

    platform_fee = 0.0
    final_price = float(base_price)
    rule = "user_commission_5pct"

    if listing_type == "shortlet":
        platform_fee = round(base_price * 0.03, 2)
        final_price = round(base_price + platform_fee, 2)
        rule = "shortlet_addon_3pct"
    elif seller_role == "merchant":
        platform_fee = round(base_price * 0.03, 2)
        final_price = round(base_price + platform_fee, 2)
        rule = "merchant_addon_3pct"
    else:
        platform_fee = round(base_price * 0.05, 2)
        final_price = float(base_price)
        rule = "user_commission_5pct"

    return jsonify({
        "ok": True,
        "base_price": float(base_price),
        "platform_fee": float(platform_fee),
        "final_price": float(final_price),
        "rule_applied": rule,
    }), 200


# ---------------------------
# Upload serving
# ---------------------------

@market_bp.get("/uploads/<path:filename>")
def get_uploaded_file(filename):
    return send_from_directory(UPLOAD_DIR, filename)


# ---------------------------
# Feed
# ---------------------------

@market_bp.get("/feed")
def get_feed():
    q = Listing.query

    state_q = (request.args.get('state') or '').strip()
    city_q = (request.args.get('city') or '').strip()
    locality_q = (request.args.get('locality') or '').strip()
    search_q = (request.args.get('q') or request.args.get('search') or '').strip()

    raw_lat = (request.args.get('lat') or '').strip()
    raw_lng = (request.args.get('lng') or '').strip()
    raw_r = (request.args.get('radius_km') or '10').strip()

    lat = None
    lng = None
    radius_km = 10.0

    try:
        lat = float(raw_lat) if raw_lat else None
    except Exception:
        lat = None
    try:
        lng = float(raw_lng) if raw_lng else None
    except Exception:
        lng = None
    try:
        radius_km = float(raw_r) if raw_r else 10.0
    except Exception:
        radius_km = 10.0

    if state_q:
        q = q.filter(Listing.state.ilike(state_q))
    if city_q:
        q = q.filter(Listing.city.ilike(city_q))
    if locality_q:
        q = q.filter(Listing.locality.ilike(locality_q))
    if search_q:
        like = f"%{search_q}%"
        q = q.filter(or_(Listing.title.ilike(like), Listing.description.ilike(like)))

    try:
        q = q.filter(or_(Listing.user_id.isnot(None), Listing.owner_id.isnot(None)))
    except Exception:
        pass

    q = _apply_listing_active_filter(q)
    q = _apply_listing_ordering(q)
    items = q.all()

    if lat is not None and lng is not None and hasattr(Listing, 'latitude') and hasattr(Listing, 'longitude'):
        filtered = []
        for it in items:
            lat_val = getattr(it, 'latitude', None)
            lng_val = getattr(it, 'longitude', None)
            if lat_val is None or lng_val is None:
                filtered.append(it)
                continue
            try:
                d = _haversine_km(lat, lng, float(lat_val), float(lng_val))
            except Exception:
                filtered.append(it)
                continue
            if d <= max(radius_km, 0.1):
                filtered.append(it)
        items = filtered

    base = _base_url()
    payload = [x.to_dict(base_url=base) for x in items]
    return jsonify({"ok": True, "items": payload, "count": len(payload)}), 200


# ---------------------------
# Listings
# ---------------------------

@market_bp.get("/listings")
def list_listings():
    q = _apply_listing_active_filter(Listing.query)
    search_q = (request.args.get('q') or request.args.get('search') or '').strip()
    if search_q:
        like = f"%{search_q}%"
        q = q.filter(or_(Listing.title.ilike(like), Listing.description.ilike(like)))
    q = _apply_listing_ordering(q)
    items = q.all()
    base = _base_url()
    return jsonify([x.to_dict(base_url=base) for x in items]), 200


@market_bp.get("/merchant/listings")
def merchant_listings():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    q = Listing.query.filter(or_(Listing.owner_id == u.id, Listing.user_id == u.id))
    q = _apply_listing_active_filter(q)
    q = _apply_listing_ordering(q)
    items = q.all()
    base = _base_url()
    return jsonify({"ok": True, "items": [x.to_dict(base_url=base) for x in items]}), 200


@market_bp.get("/listings/<int:listing_id>")
def get_listing(listing_id: int):
    item = Listing.query.get(listing_id)
    if not item:
        return jsonify({"message": "Not found"}), 404
    return jsonify({"ok": True, "listing": item.to_dict(base_url=_base_url())}), 200


@market_bp.put("/listings/<int:listing_id>")
def update_listing(listing_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    item = Listing.query.get(listing_id)
    if not item:
        return jsonify({"message": "Not found"}), 404
    if not (_is_owner(u, item) or _is_admin(u)):
        return jsonify({"message": "Forbidden"}), 403
    if not _is_admin(u) and not _is_email_verified(u):
        return jsonify({"message": "Email verification required"}), 403

    payload = request.get_json(silent=True) or {}
    # Listing cap enforcement on activation
    try:
        current_active = _is_active_listing(item)
    except Exception:
        current_active = True
    new_active = current_active
    if "is_active" in payload:
        new_active = bool(payload.get("is_active"))
    elif "disabled" in payload:
        new_active = not bool(payload.get("disabled"))
    elif "is_disabled" in payload:
        new_active = not bool(payload.get("is_disabled"))
    elif "status" in payload:
        new_active = str(payload.get("status") or "").strip().lower() not in ("disabled", "inactive")

    if new_active and not current_active:
        account_role = _account_role(int(u.id))
        ok, info = enforce_listing_cap(int(u.id), account_role, "declutter")
        if not ok:
            return jsonify(info), 403
    title = payload.get("title")
    if title is not None:
        title = str(title).strip()
        if not title:
            return jsonify({"message": "title cannot be empty"}), 400
        item.title = title

    if "description" in payload:
        item.description = (payload.get("description") or "").strip()
    if "state" in payload:
        item.state = (payload.get("state") or "").strip()
    if "city" in payload:
        item.city = (payload.get("city") or "").strip()
    if "locality" in payload:
        item.locality = (payload.get("locality") or "").strip()
    if "price" in payload:
        try:
            base_price = float(payload.get("price") or 0.0)
            owner_id = None
            try:
                owner_id = int(item.owner_id) if item.owner_id else None
            except Exception:
                owner_id = None
            if owner_id is None:
                try:
                    owner_id = int(item.user_id) if item.user_id else None
                except Exception:
                    owner_id = None
            _apply_pricing_for_listing(item, base_price=base_price, seller_role=_seller_role(owner_id))
        except Exception:
            item.price = 0.0
    if "image_path" in payload or "image" in payload:
        incoming = (payload.get("image_path") or payload.get("image") or "").strip()
        if incoming:
            item.image_path = incoming

    try:
        db.session.add(item)
        db.session.commit()
        return jsonify({"ok": True, "listing": item.to_dict(base_url=_base_url())}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Update failed", "error": str(e)}), 500


@market_bp.delete("/listings/<int:listing_id>")
def delete_listing(listing_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    item = Listing.query.get(listing_id)
    if not item:
        return jsonify({"message": "Not found"}), 404
    if not (_is_owner(u, item) or _is_admin(u)):
        return jsonify({"message": "Forbidden"}), 403
    if not _is_admin(u) and not _is_email_verified(u):
        return jsonify({"message": "Email verification required"}), 403

    try:
        db.session.delete(item)
        db.session.commit()
        return jsonify({"ok": True, "deleted": True, "listing_id": listing_id}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Delete failed", "error": str(e)}), 500


@market_bp.post("/listings")
def create_listing():
    """
    Supports BOTH:
    - multipart/form-data (recommended): fields + file "image"
    - JSON body (fallback): title, description, price, image_path or image

    Stores:
      image_path = "/api/uploads/<filename>"  (preferred)
    Returns:
      image = "<base_url>/api/uploads/<filename>" via Listing.to_dict(base_url=...)
    """
    title = ""
    description = ""
    price = 0.0
    stored_image_path = ""
    state = ""
    city = ""
    locality = ""  # store RELATIVE path: /api/uploads/<filename>

    # 1) Multipart upload
    if request.content_type and "multipart/form-data" in (request.content_type or ""):
        title = (request.form.get("title") or "").strip()
        description = (request.form.get("description") or "").strip()

        state = (request.form.get("state") or "").strip()
        city = (request.form.get("city") or "").strip()
        locality = (request.form.get("locality") or "").strip()

        raw_price = request.form.get("price")
        try:
            price = float(raw_price) if raw_price is not None and str(raw_price).strip() != "" else 0.0
        except Exception:
            price = 0.0

        file = request.files.get("image")
        if file and file.filename:
            original = secure_filename(os.path.basename(file.filename))

            if not _is_allowed(original):
                return jsonify({"message": "Invalid image type. Use jpg/jpeg/png/webp."}), 400

            ts = int(datetime.utcnow().timestamp())
            safe_name = f"{ts}_{original}" if original else f"{ts}_upload.jpg"

            save_path = os.path.join(UPLOAD_DIR, safe_name)
            file.save(save_path)

            # Store RELATIVE path in DB (portable across emulator/localhost/prod)
            stored_image_path = f"/api/uploads/{safe_name}"

    # 2) JSON fallback
    else:
        payload = request.get_json(silent=True) or {}
        title = (payload.get("title") or "").strip()
        description = (payload.get("description") or "").strip()

        state = (payload.get("state") or "").strip()
        city = (payload.get("city") or "").strip()
        locality = (payload.get("locality") or "").strip()

        raw_price = payload.get("price")
        try:
            price = float(raw_price) if raw_price is not None and str(raw_price).strip() != "" else 0.0
        except Exception:
            price = 0.0

        # Accept either image_path or image.
        # If client sends absolute URL, we keep it (legacy-safe).
        incoming = (payload.get("image_path") or payload.get("image") or "").strip()
        if incoming:
            stored_image_path = incoming

    if not title:
        return jsonify({"message": "title is required"}), 400

    # Best-effort: attach listing to authenticated user
    owner_id = None
    try:
        token = get_bearer_token(request.headers.get("Authorization", ""))
        payload = decode_token(token) if token else None
        sub = payload.get("sub") if isinstance(payload, dict) else None
        owner_id = int(sub) if sub is not None and str(sub).isdigit() else None
    except Exception:
        owner_id = None

    if owner_id is None:
        return jsonify({"message": "Unauthorized"}), 401
    try:
        owner_user = User.query.get(int(owner_id))
    except Exception:
        owner_user = None
    if not _is_email_verified(owner_user):
        return jsonify({"message": "Verify your email to create listings"}), 403

    account_role = _account_role(owner_id)
    ok, info = enforce_listing_cap(int(owner_id), account_role, "declutter")
    if not ok:
        return jsonify(info), 403

    listing = Listing(
        owner_id=owner_id,
        title=title,
        state=state,
        city=city,
        locality=locality,
        description=description,
        price=price,
        image_path=stored_image_path,
    )

    try:
        seller_role = _seller_role(owner_id)
    except Exception:
        seller_role = "guest"
    _apply_pricing_for_listing(listing, base_price=price, seller_role=seller_role)

    try:
        db.session.add(listing)
        db.session.commit()

        base = _base_url()
        return jsonify({"ok": True, "listing": listing.to_dict(base_url=base)}), 201

    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to create listing", "error": str(e)}), 500


# ---------------------------
# Optional: One-time repair tool
# ---------------------------
# Run once to convert old rows that stored absolute URLs into relative paths.
# Then REMOVE this endpoint.

@market_bp.post("/admin/repair-images")
def repair_images():
    """
    Converts stored absolute URLs like:
      http://127.0.0.1:5000/api/uploads/x.jpg
    into:
      /api/uploads/x.jpg
    """
    items = Listing.query.all()
    changed = 0

    for x in items:
        p = (x.image_path or "").strip()
        if not p:
            continue

        low = p.lower()
        if low.startswith("http://") or low.startswith("https://"):
            idx = low.find("/api/uploads/")
            if idx != -1:
                x.image_path = p[idx:]  # keep original substring from /api/uploads/...
                changed += 1

    try:
        db.session.commit()
        return jsonify({"ok": True, "changed": changed}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"ok": False, "error": str(e)}), 500
