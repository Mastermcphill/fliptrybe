from __future__ import annotations

import os
from datetime import datetime

from sqlalchemy import text, or_
from flask import Blueprint, jsonify, request, send_from_directory, current_app
from werkzeug.utils import secure_filename

from app.extensions import db
from app.utils.ng_locations import NIGERIA_LOCATIONS
from app.models import User, Listing, ItemDictionary, UserSettings
from app.utils.commission import compute_commission, RATES
from app.utils.listing_caps import enforce_listing_cap
from app.utils.jwt_utils import decode_token, get_bearer_token
from app.utils.autopilot import get_settings
from app.services.search_v2_service import search_listings_v2
from app.utils.rate_limit import check_limit
from app.services.risk_engine_service import record_event
from app.services.discovery_service import (
    ranking_for_listing,
    set_listing_favorite,
    record_listing_view,
    merchant_listing_metrics,
    queue_item_unavailable_notifications,
)


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
        if listing.user_id and int(listing.user_id) == int(u.id):
            return True
    except Exception:
        pass
    return False


def _user_preferences(user: User | None) -> tuple[str, str]:
    if not user:
        return "", ""
    try:
        s = UserSettings.query.filter_by(user_id=int(user.id)).first()
    except Exception:
        s = None
    if not s:
        return "", ""
    return (str(getattr(s, "preferred_city", "") or "").strip(), str(getattr(s, "preferred_state", "") or "").strip())


def _search_args():
    def _to_bool(raw: str | None):
        if raw is None:
            return None
        value = str(raw).strip().lower()
        if value in ("1", "true", "yes", "on"):
            return True
        if value in ("0", "false", "no", "off"):
            return False
        return None

    q = (request.args.get("q") or "").strip()
    category = (request.args.get("category") or "").strip()
    state = (request.args.get("state") or "").strip()
    condition = (request.args.get("condition") or "").strip()
    status = (request.args.get("status") or "").strip()
    sort = (request.args.get("sort") or "relevance").strip().lower()
    min_price_raw = request.args.get("min_price")
    if min_price_raw in (None, ""):
        min_price_raw = request.args.get("price_min")
    max_price_raw = request.args.get("max_price")
    if max_price_raw in (None, ""):
        max_price_raw = request.args.get("price_max")
    try:
        min_price = float(min_price_raw) if min_price_raw not in (None, "") else None
    except Exception:
        min_price = None
    try:
        max_price = float(max_price_raw) if max_price_raw not in (None, "") else None
    except Exception:
        max_price = None
    try:
        limit = int(request.args.get("limit") or 20)
    except Exception:
        limit = 20
    try:
        offset = int(request.args.get("offset") or 0)
    except Exception:
        offset = 0
    return {
        "q": q,
        "category": category,
        "state": state,
        "condition": condition,
        "status": status,
        "sort": sort,
        "min_price": min_price,
        "max_price": max_price,
        "delivery_available": _to_bool(request.args.get("delivery_available")),
        "inspection_required": _to_bool(request.args.get("inspection_required")),
        "limit": max(1, min(limit, 100)),
        "offset": max(0, offset),
    }


def _normalize_ranking_reason(value) -> list[str]:
    if isinstance(value, list):
        return [str(x) for x in value if str(x).strip()]
    if isinstance(value, tuple):
        return [str(x) for x in list(value) if str(x).strip()]
    if value:
        return [str(value)]
    return []


def _listing_item_from_raw(raw: dict | None, *, ranking_score: int = 0, ranking_reason=None) -> dict:
    row = dict(raw or {})
    image_path = str(row.get("image_path") or "").strip()
    image = str(row.get("image") or "").strip() or image_path
    created_at = row.get("created_at")
    if created_at is not None:
        created_at = str(created_at)
    reasons = _normalize_ranking_reason(ranking_reason if ranking_reason is not None else row.get("ranking_reason"))
    if not reasons:
        reasons = ["BASELINE"]
    return {
        "id": int(row.get("id") or 0),
        "user_id": int(row.get("user_id") or row.get("owner_id") or 0),
        "owner_id": int(row.get("owner_id") or row.get("user_id") or 0),
        "title": str(row.get("title") or ""),
        "description": str(row.get("description") or ""),
        "category": str(row.get("category") or ""),
        "state": str(row.get("state") or ""),
        "city": str(row.get("city") or ""),
        "locality": str(row.get("locality") or ""),
        "condition": str(row.get("condition") or ""),
        "image": image,
        "image_path": image_path,
        "image_filename": str(row.get("image_filename") or ""),
        "price": float(row.get("price") or row.get("final_price") or 0.0),
        "base_price": float(row.get("base_price") or row.get("price") or 0.0),
        "platform_fee": float(row.get("platform_fee") or 0.0),
        "final_price": float(row.get("final_price") or row.get("price") or 0.0),
        "is_active": bool(row.get("is_active", True)),
        "views_count": int(row.get("views_count") or 0),
        "favorites_count": int(row.get("favorites_count") or 0),
        "heat_level": str(row.get("heat_level") or "normal"),
        "heat_score": int(row.get("heat_score") or 0),
        "created_at": created_at,
        "ranking_score": int(ranking_score if ranking_score is not None else row.get("ranking_score") or 0),
        "ranking_reason": reasons,
    }


def _normalize_search_payload(
    payload: dict | None,
    *,
    city: str = "",
    state: str = "",
    limit: int = 20,
    offset: int = 0,
    sort: str = "relevance",
    q: str = "",
) -> dict:
    src = payload if isinstance(payload, dict) else {}
    raw_items = src.get("items")
    if not isinstance(raw_items, list):
        raw_items = []
    items = [_listing_item_from_raw(item) for item in raw_items if isinstance(item, dict)]
    supported = src.get("supported_filters")
    if not isinstance(supported, dict):
        supported = {}
    return {
        "ok": bool(src.get("ok", True)),
        "city": city,
        "state": state,
        "items": items,
        "total": int(src.get("total") or len(items)),
        "limit": int(src.get("limit") or limit),
        "offset": int(src.get("offset") or offset),
        "sort": str(src.get("sort") or sort),
        "q": str(src.get("q") or q),
        "supported_filters": {
            "delivery_available": bool(supported.get("delivery_available", False)),
            "inspection_required": bool(supported.get("inspection_required", False)),
        },
    }


def _rate_limit_response(action: str, *, user: User | None, limit: int, window_seconds: int):
    try:
        settings = get_settings()
        enabled = bool(getattr(settings, "rate_limit_enabled", True))
    except Exception:
        enabled = True
    if not enabled:
        return None
    ip = (request.headers.get("X-Forwarded-For") or request.remote_addr or "unknown").split(",")[0].strip()
    uid = int(getattr(user, "id", 0) or 0) if user else 0
    key = f"{action}:ip:{ip}:u:{uid}"
    ok, retry_after = check_limit(key, limit=limit, window_seconds=window_seconds)
    if ok:
        return None
    try:
        record_event(
            action,
            user=user,
            context={"rate_limited": True, "reason_code": "RATE_LIMIT_EXCEEDED", "retry_after": retry_after},
            request_id=request.headers.get("X-Request-Id"),
        )
    except Exception:
        db.session.rollback()
    return jsonify({"ok": False, "error": "RATE_LIMITED", "message": "Too many listing actions. Retry later.", "retry_after": retry_after}), 429


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


@market_bp.get("/public/features")
def public_features():
    settings = get_settings()
    mode = (getattr(settings, "search_v2_mode", None) or "off").strip().lower()
    if mode not in ("off", "shadow", "on"):
        mode = "off"
    return jsonify(
        {
            "ok": True,
            "features": {
                "search_v2_mode": mode,
                "city_discovery_v1": bool(getattr(settings, "city_discovery_v1", True)),
                "views_heat_v1": bool(getattr(settings, "views_heat_v1", True)),
                "cart_checkout_v1": bool(getattr(settings, "cart_checkout_v1", False)),
                "shortlet_reels_v1": bool(getattr(settings, "shortlet_reels_v1", False)),
                "watcher_notifications_v1": bool(getattr(settings, "watcher_notifications_v1", False)),
            },
        }
    ), 200


@market_bp.get("/public/listings/search")
def public_listings_search():
    args = _search_args()
    pref_city = (request.args.get("city") or "").strip()
    pref_state = (request.args.get("state") or "").strip()
    u = _current_user()
    if not pref_city and not pref_state:
        user_city, user_state = _user_preferences(u)
        pref_city = user_city or pref_city
        pref_state = user_state or pref_state
    try:
        raw_payload = search_listings_v2(
            q=args["q"],
            category=args["category"],
            state=args["state"],
            min_price=args["min_price"],
            max_price=args["max_price"],
            condition=args["condition"],
            status=args["status"],
            delivery_available=args["delivery_available"],
            inspection_required=args["inspection_required"],
            sort=args["sort"],
            limit=args["limit"],
            offset=args["offset"],
            include_inactive=False,
            preferred_city=pref_city,
            preferred_state=pref_state,
        )
        payload = _normalize_search_payload(
            raw_payload,
            city=pref_city,
            state=pref_state,
            limit=args["limit"],
            offset=args["offset"],
            sort=args["sort"],
            q=args["q"],
        )
        return jsonify(payload), 200
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        try:
            current_app.logger.exception("public_listings_search_failed")
        except Exception:
            pass
        payload = _normalize_search_payload(
            {},
            city=pref_city,
            state=pref_state,
            limit=args["limit"],
            offset=args["offset"],
            sort=args["sort"],
            q=args["q"],
        )
        return jsonify(payload), 200


@market_bp.get("/admin/listings/search")
def admin_listings_search():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    args = _search_args()
    pref_city = (request.args.get("city") or "").strip()
    pref_state = (request.args.get("state") or "").strip()
    try:
        raw_payload = search_listings_v2(
            q=args["q"],
            category=args["category"],
            state=args["state"],
            min_price=args["min_price"],
            max_price=args["max_price"],
            condition=args["condition"],
            status=args["status"],
            delivery_available=args["delivery_available"],
            inspection_required=args["inspection_required"],
            sort=args["sort"],
            limit=args["limit"],
            offset=args["offset"],
            include_inactive=True,
            preferred_city=pref_city,
            preferred_state=pref_state,
        )
        payload = _normalize_search_payload(
            raw_payload,
            city=pref_city,
            state=pref_state,
            limit=args["limit"],
            offset=args["offset"],
            sort=args["sort"],
            q=args["q"],
        )
        return jsonify(payload), 200
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        try:
            current_app.logger.exception("admin_listings_search_failed")
        except Exception:
            pass
        payload = _normalize_search_payload(
            {},
            city=pref_city,
            state=pref_state,
            limit=args["limit"],
            offset=args["offset"],
            sort=args["sort"],
            q=args["q"],
        )
        return jsonify(payload), 200


@market_bp.get("/public/listings/recommended")
def public_listings_recommended():
    limit_raw = request.args.get("limit") or "20"
    try:
        limit = max(1, min(int(limit_raw), 60))
    except Exception:
        limit = 20
    city = (request.args.get("city") or "").strip()
    state = (request.args.get("state") or "").strip()
    u = _current_user()
    if not city and not state:
        pref_city, pref_state = _user_preferences(u)
        city = pref_city or city
        state = pref_state or state
    rows = _apply_listing_ordering(_apply_listing_active_filter(Listing.query)).limit(500).all()
    ranked = []
    for row in rows:
        score, reasons = ranking_for_listing(row, preferred_city=city, preferred_state=state)
        payload = _listing_item_from_raw(row.to_dict(base_url=_base_url()), ranking_score=int(score), ranking_reason=reasons)
        ranked.append(payload)
    ranked.sort(key=lambda item: (int(item.get("ranking_score", 0)), item.get("created_at") or ""), reverse=True)
    return jsonify({"ok": True, "city": city, "state": state, "items": ranked[:limit], "limit": limit}), 200


@market_bp.get("/public/listings/title-suggestions")
def listing_title_suggestions():
    q = (request.args.get("q") or "").strip().lower()
    try:
        limit = max(1, min(int(request.args.get("limit") or 10), 25))
    except Exception:
        limit = 10
    if not q:
        rows = ItemDictionary.query.order_by(ItemDictionary.popularity_score.desc(), ItemDictionary.term.asc()).limit(limit).all()
    else:
        rows = (
            ItemDictionary.query
            .filter(ItemDictionary.term.ilike(f"%{q}%"))
            .order_by(ItemDictionary.popularity_score.desc(), ItemDictionary.term.asc())
            .limit(limit)
            .all()
        )
    items = [{"term": row.term, "category": row.category, "popularity_score": int(row.popularity_score or 0)} for row in rows]
    return jsonify({"ok": True, "items": items, "q": q, "limit": limit}), 200


@market_bp.get("/public/search")
def public_global_search():
    q = (request.args.get("q") or "").strip()
    city = (request.args.get("city") or "").strip()
    state = (request.args.get("state") or "").strip()
    try:
        limit = max(1, min(int(request.args.get("limit") or 8), 30))
    except Exception:
        limit = 8
    listings_payload = search_listings_v2(
        q=q,
        state=state,
        limit=limit,
        offset=0,
        include_inactive=False,
        preferred_city=city,
        preferred_state=state,
    )
    listing_items = listings_payload.get("items", []) if isinstance(listings_payload, dict) else []
    shortlet_rows = []
    try:
        from app.models import Shortlet, MerchantProfile
        sq = Shortlet.query
        if city:
            sq = sq.filter(Shortlet.city.ilike(city))
        elif state:
            sq = sq.filter(Shortlet.state.ilike(state))
        if q:
            like = f"%{q}%"
            sq = sq.filter(or_(Shortlet.title.ilike(like), Shortlet.description.ilike(like), Shortlet.city.ilike(like)))
        shortlet_rows = sq.order_by(Shortlet.created_at.desc()).limit(limit).all()
        shortlet_items = [row.to_dict(base_url=_base_url()) for row in shortlet_rows]
        mq = MerchantProfile.query
        if q:
            like = f"%{q}%"
            mq = mq.filter(or_(MerchantProfile.business_name.ilike(like), MerchantProfile.city.ilike(like), MerchantProfile.state.ilike(like)))
        merchant_rows = mq.order_by(MerchantProfile.score.desc()).limit(limit).all()
        merchant_items = [row.to_dict() for row in merchant_rows]
    except Exception:
        db.session.rollback()
        shortlet_items = []
        merchant_items = []
    return jsonify({"ok": True, "items": listing_items, "shortlets": shortlet_items, "merchants": merchant_items, "q": q, "city": city, "state": state}), 200


@market_bp.get("/public/search/suggest")
def public_global_search_suggest():
    q = (request.args.get("q") or "").strip().lower()
    city = (request.args.get("city") or "").strip()
    try:
        limit = max(1, min(int(request.args.get("limit") or 8), 20))
    except Exception:
        limit = 8

    terms = []
    seen = set()
    if q:
        rows = (
            ItemDictionary.query
            .filter(ItemDictionary.term.ilike(f"%{q}%"))
            .order_by(ItemDictionary.popularity_score.desc(), ItemDictionary.term.asc())
            .limit(limit)
            .all()
        )
    else:
        rows = ItemDictionary.query.order_by(ItemDictionary.popularity_score.desc()).limit(limit).all()
    for row in rows:
        t = (row.term or "").strip()
        if not t:
            continue
        key = t.lower()
        if key in seen:
            continue
        seen.add(key)
        terms.append(t)
        if len(terms) >= limit:
            break

    if len(terms) < limit:
        like = f"%{q}%" if q else "%"
        rows = (
            Listing.query
            .filter(Listing.title.ilike(like))
            .order_by(Listing.created_at.desc())
            .limit(limit * 2)
            .all()
        )
        for row in rows:
            t = (row.title or "").strip()
            if not t:
                continue
            key = t.lower()
            if key in seen:
                continue
            seen.add(key)
            terms.append(t)
            if len(terms) >= limit:
                break

    return jsonify({"ok": True, "items": terms, "q": q, "city": city, "limit": limit}), 200


@market_bp.post("/listings/<int:listing_id>/favorite")
def favorite_listing(listing_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    try:
        payload = set_listing_favorite(listing_id=int(listing_id), user_id=int(u.id), is_favorite=True)
        if not payload.get("ok"):
            return jsonify(payload), 404
        return jsonify(payload), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "FAVORITE_FAILED", "message": str(exc)}), 500


@market_bp.delete("/listings/<int:listing_id>/favorite")
def unfavorite_listing(listing_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    try:
        payload = set_listing_favorite(listing_id=int(listing_id), user_id=int(u.id), is_favorite=False)
        if not payload.get("ok"):
            return jsonify(payload), 404
        return jsonify(payload), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "UNFAVORITE_FAILED", "message": str(exc)}), 500


@market_bp.post("/listings/<int:listing_id>/view")
def view_listing(listing_id: int):
    u = _current_user()
    session_key = (request.headers.get("X-Session-Key") or request.args.get("session_key") or "").strip()
    try:
        payload = record_listing_view(
            listing_id=int(listing_id),
            user_id=int(u.id) if u else None,
            session_key=session_key,
        )
        if not payload.get("ok"):
            return jsonify(payload), 404
        return jsonify(payload), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "VIEW_RECORD_FAILED", "message": str(exc)}), 500


@market_bp.get("/merchant/listings/metrics")
def merchant_listings_metrics():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    role = (getattr(u, "role", None) or "").strip().lower()
    if role not in ("merchant", "admin"):
        return jsonify({"message": "Forbidden"}), 403
    merchant_id = int(u.id)
    if role == "admin":
        try:
            merchant_id = int(request.args.get("merchant_id") or merchant_id)
        except Exception:
            merchant_id = int(u.id)
    items = merchant_listing_metrics(int(merchant_id))
    return jsonify({"ok": True, "merchant_id": int(merchant_id), "items": items}), 200


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
        q = q.filter(Listing.user_id.isnot(None))
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
    try:
        q = _apply_listing_active_filter(Listing.query)
        search_q = (request.args.get('q') or request.args.get('search') or '').strip()
        if search_q:
            like = f"%{search_q}%"
            q = q.filter(or_(Listing.title.ilike(like), Listing.description.ilike(like)))
        q = _apply_listing_ordering(q)
        items = q.all()
        base = _base_url()
        return jsonify([x.to_dict(base_url=base) for x in items]), 200
    except Exception as e:
        db.session.rollback()
        try:
            current_app.logger.exception("listings_list_failed")
        except Exception:
            pass
        detail = None
        try:
            u = _current_user()
            if request.headers.get("X-Debug", "").strip() == "1" and _is_admin(u):
                detail = f"{type(e).__name__}: {e}"
        except Exception:
            detail = None
        if detail:
            return jsonify({"ok": False, "error": "db_error", "detail": detail}), 500
        return jsonify({"ok": False, "error": "db_error"}), 500


@market_bp.get("/merchant/listings")
def merchant_listings():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    q = Listing.query.filter(Listing.user_id == u.id)
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
    rl = _rate_limit_response("listing_update", user=u, limit=60, window_seconds=300)
    if rl is not None:
        return rl
    item = Listing.query.get(listing_id)
    if not item:
        return jsonify({"message": "Not found"}), 404
    if not (_is_owner(u, item) or _is_admin(u)):
        return jsonify({"message": "Forbidden"}), 403
    if not _is_admin(u) and not _is_email_verified(u):
        return jsonify({"error": "EMAIL_NOT_VERIFIED", "message": "Your email must be verified to perform this action"}), 403

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
            seller_id = None
            try:
                seller_id = int(item.user_id) if item.user_id else None
            except Exception:
                seller_id = None
            _apply_pricing_for_listing(item, base_price=base_price, seller_role=_seller_role(seller_id))
        except Exception:
            item.price = 0.0
    if "image_path" in payload or "image" in payload:
        incoming = (payload.get("image_path") or payload.get("image") or "").strip()
        if incoming:
            item.image_path = incoming

    try:
        try:
            record_event(
                "listing_update",
                user=u,
                context={"listing_id": int(item.id), "title": item.title or "", "state": item.state or ""},
                request_id=request.headers.get("X-Request-Id"),
            )
        except Exception:
            db.session.rollback()
        db.session.add(item)
        db.session.commit()
        if current_active and not new_active:
            try:
                queue_item_unavailable_notifications(entity="listing", entity_id=int(item.id), title=item.title or "Listing")
            except Exception:
                db.session.rollback()
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
        return jsonify({"error": "EMAIL_NOT_VERIFIED", "message": "Your email must be verified to perform this action"}), 403

    try:
        try:
            queue_item_unavailable_notifications(entity="listing", entity_id=int(item.id), title=item.title or "Listing")
        except Exception:
            db.session.rollback()
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
    user_id = None
    try:
        token = get_bearer_token(request.headers.get("Authorization", ""))
        payload = decode_token(token) if token else None
        sub = payload.get("sub") if isinstance(payload, dict) else None
        user_id = int(sub) if sub is not None and str(sub).isdigit() else None
    except Exception:
        user_id = None

    if user_id is None:
        return jsonify({"message": "Unauthorized"}), 401
    try:
        owner_user = User.query.get(int(user_id))
    except Exception:
        owner_user = None
    rl = _rate_limit_response("listing_create", user=owner_user, limit=40, window_seconds=300)
    if rl is not None:
        return rl
    if not _is_email_verified(owner_user):
        return jsonify({"error": "EMAIL_NOT_VERIFIED", "message": "Your email must be verified to perform this action"}), 403

    account_role = _account_role(user_id)
    ok, info = enforce_listing_cap(int(user_id), account_role, "declutter")
    if not ok:
        return jsonify(info), 403

    listing = Listing(
        user_id=user_id,
        title=title,
        state=state,
        city=city,
        locality=locality,
        description=description,
        price=price,
        image_path=stored_image_path,
    )

    try:
        seller_role = _seller_role(user_id)
    except Exception:
        seller_role = "guest"
    _apply_pricing_for_listing(listing, base_price=price, seller_role=seller_role)

    try:
        try:
            record_event(
                "listing_create",
                user=owner_user,
                context={"title": title[:120], "state": state or "", "price": float(price or 0.0)},
                request_id=request.headers.get("X-Request-Id"),
            )
        except Exception:
            db.session.rollback()
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
