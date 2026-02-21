from __future__ import annotations

import os
import json
from datetime import datetime

from sqlalchemy import text, or_
from flask import Blueprint, jsonify, request, send_from_directory, current_app
from werkzeug.exceptions import BadRequest
from werkzeug.utils import secure_filename

from app.extensions import db
from app.utils.ng_locations import NIGERIA_LOCATIONS
from app.models import (
    User,
    Listing,
    SavedSearch,
    AuditLog,
    ItemDictionary,
    UserSettings,
    Category,
    Brand,
    BrandModel,
    MerchantProfile,
    ImageFingerprint,
)
from app.utils.commission import compute_commission, RATES
from app.utils.listing_caps import enforce_listing_cap
from app.utils.jwt_utils import decode_token, get_bearer_token
from app.utils.autopilot import get_settings
from app.services.search_v2_service import search_listings_v2
from app.services.search import (
    search_engine_is_meili,
    search_fallback_sql_enabled,
    listings_index_name,
)
from app.services.search.meili_client import (
    get_meili_client,
    SearchNotInitialized,
    SearchUnavailable,
)
from app.services.listing_metadata_schema import (
    CATEGORY_GROUPS,
    slugify,
    schema_for_category,
    validate_category_metadata,
)
from app.utils.rate_limit import check_limit
from app.utils.cache_layer import (
    build_cache_key,
    get_json,
    set_json,
    delete,
    delete_prefix,
    listing_detail_cache_ttl_seconds,
    feed_cache_ttl_seconds,
)
from app.services.risk_engine_service import record_event
from app.services.image_dedupe_service import ensure_image_unique, DuplicateImageError
from app.services.discovery_service import (
    ranking_for_listing,
    set_listing_favorite,
    record_listing_view,
    merchant_listing_metrics,
    queue_item_unavailable_notifications,
)
from app.utils.observability import get_request_id
from app.utils.content_moderation import (
    CONTACT_BLOCK_MESSAGE,
    DESCRIPTION_BLOCK_MESSAGE,
    contains_prohibited_listing_description,
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
    return bool(getattr(u, "is_admin", False))

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
    def _to_int(raw):
        if raw in (None, ""):
            return None
        try:
            value = int(str(raw).strip())
            return value if value > 0 else None
        except Exception:
            return None

    def _to_bool(raw: str | None):
        if raw is None:
            return None
        value = str(raw).strip().lower()
        if value in ("1", "true", "yes", "on"):
            return True
        if value in ("0", "false", "no", "off"):
            return False
        return None

    def _to_float(raw):
        if raw in (None, ""):
            return None
        try:
            return float(str(raw).strip())
        except Exception:
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
        "category_id": _to_int(request.args.get("category_id")),
        "parent_category_id": _to_int(request.args.get("parent_category_id")),
        "brand_id": _to_int(request.args.get("brand_id")),
        "model_id": _to_int(request.args.get("model_id")),
        "listing_type": (request.args.get("listing_type") or "").strip().lower(),
        "make": (request.args.get("make") or "").strip(),
        "model": (request.args.get("model") or "").strip(),
        "year": _to_int(request.args.get("year")),
        "battery_type": (request.args.get("battery_type") or "").strip(),
        "inverter_capacity": (request.args.get("inverter_capacity") or "").strip(),
        "lithium_only": _to_bool(request.args.get("lithium_only")),
        "property_type": (request.args.get("property_type") or "").strip(),
        "bedrooms_min": _to_int(request.args.get("bedrooms_min")),
        "bedrooms_max": _to_int(request.args.get("bedrooms_max")),
        "bathrooms_min": _to_int(request.args.get("bathrooms_min")),
        "bathrooms_max": _to_int(request.args.get("bathrooms_max")),
        "furnished": _to_bool(request.args.get("furnished")),
        "serviced": _to_bool(request.args.get("serviced")),
        "land_size_min": _to_float(request.args.get("land_size_min")),
        "land_size_max": _to_float(request.args.get("land_size_max")),
        "title_document_type": (request.args.get("title_document_type") or request.args.get("document_type") or "").strip(),
        "city": (request.args.get("city") or "").strip(),
        "area": (request.args.get("area") or "").strip(),
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


def _descendant_category_ids(parent_id: int) -> list[int]:
    try:
        rows = Category.query.with_entities(Category.id, Category.parent_id).all()
    except Exception:
        return []
    by_parent: dict[int, list[int]] = {}
    for cid, pid in rows:
        if cid is None:
            continue
        key = int(pid) if pid is not None else 0
        by_parent.setdefault(key, []).append(int(cid))
    out: list[int] = []
    seen: set[int] = set()
    stack = [int(parent_id)]
    while stack:
        current = stack.pop()
        if current in seen:
            continue
        seen.add(current)
        out.append(current)
        for child in by_parent.get(current, []):
            if child not in seen:
                stack.append(child)
    return out


def _normalize_ranking_reason(value) -> list[str]:
    if isinstance(value, list):
        return [str(x) for x in value if str(x).strip()]
    if isinstance(value, tuple):
        return [str(x) for x in list(value) if str(x).strip()]
    if value:
        return [str(value)]
    return []


def _maybe_int(value):
    if value in (None, ""):
        return None
    try:
        return int(value)
    except Exception:
        return None


def _maybe_float(value):
    if value in (None, ""):
        return None
    try:
        return float(value)
    except Exception:
        return None


def _maybe_bool(value):
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return int(value) == 1
    text_value = str(value).strip().lower()
    if text_value in ("1", "true", "yes", "y", "on"):
        return True
    if text_value in ("0", "false", "no", "n", "off"):
        return False
    return None


def _parse_json_map(raw_value) -> dict:
    if isinstance(raw_value, dict):
        return dict(raw_value)
    text_value = str(raw_value or "").strip()
    if not text_value:
        return {}
    try:
        parsed = json.loads(text_value)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        return {}
    return {}


def _category_rows_by_id() -> dict[int, dict]:
    try:
        rows = Category.query.with_entities(Category.id, Category.name, Category.slug, Category.parent_id).all()
    except Exception:
        return {}
    out: dict[int, dict] = {}
    for row_id, name, slug, parent_id in rows:
        if row_id is None:
            continue
        out[int(row_id)] = {
            "id": int(row_id),
            "name": str(name or ""),
            "slug": str(slug or ""),
            "parent_id": int(parent_id) if parent_id is not None else None,
        }
    return out


def _category_group_slug_from_leaf_slug(category_slug: str) -> str:
    slug = slugify(category_slug)
    for group in CATEGORY_GROUPS:
        gslug = slugify(group.get("slug") or "")
        if not gslug:
            continue
        if slug == gslug:
            return gslug
        for sub in group.get("subcategories") or []:
            if slugify(sub.get("slug") or "") == slug:
                return gslug
    return ""


def _resolve_category_context(*, category_id: int | None, category_name: str = "") -> dict:
    rows_by_id = _category_rows_by_id()
    category_row = rows_by_id.get(int(category_id)) if category_id is not None else None

    root_row = category_row
    if category_row is not None:
        seen: set[int] = set()
        while root_row is not None and root_row.get("parent_id") is not None:
            parent_id = int(root_row["parent_id"])
            if parent_id in seen:
                break
            seen.add(parent_id)
            root_row = rows_by_id.get(parent_id)

    category_slug = ""
    if category_row is not None:
        category_slug = slugify(category_row.get("slug") or category_row.get("name") or "")
    if not category_slug:
        category_slug = slugify(category_name)

    group_slug = ""
    if root_row is not None:
        group_slug = slugify(root_row.get("slug") or root_row.get("name") or "")
    if not group_slug:
        group_slug = _category_group_slug_from_leaf_slug(category_slug)

    return {
        "category_id": int(category_row["id"]) if category_row is not None else category_id,
        "category_name": str(category_row.get("name") or category_name or "") if category_row is not None else str(category_name or ""),
        "category_slug": category_slug,
        "group_id": int(root_row["id"]) if root_row is not None else None,
        "group_name": str(root_row.get("name") or "") if root_row is not None else "",
        "group_slug": group_slug,
    }


def _category_schema_payload(*, category_id: int | None, category_name: str = "") -> dict:
    context = _resolve_category_context(category_id=category_id, category_name=category_name)
    schema = schema_for_category(
        group_slug=str(context.get("group_slug") or ""),
        category_slug=str(context.get("category_slug") or ""),
    )
    return {
        "ok": True,
        "category": {
            "id": context.get("category_id"),
            "name": context.get("category_name") or "",
            "slug": context.get("category_slug") or "",
        },
        "category_group": {
            "id": context.get("group_id"),
            "name": context.get("group_name") or "",
            "slug": context.get("group_slug") or "",
        },
        "schema": schema,
    }


def _normalize_approval_status(raw_value, *, fallback: str = "approved") -> str:
    value = str(raw_value or "").strip().lower()
    if value in ("approved", "pending", "rejected"):
        return value
    return fallback


def _apply_vertical_metadata_to_listing(
    listing: Listing,
    *,
    category_id: int | None,
    category_name: str = "",
    listing_type_raw: str = "",
    vehicle_payload: dict | None = None,
    energy_payload: dict | None = None,
    real_estate_payload: dict | None = None,
    delivery_available_raw=None,
    inspection_required_raw=None,
    is_admin: bool = False,
    approval_status_raw: str = "",
) -> tuple[bool, dict | None]:
    context = _resolve_category_context(category_id=category_id, category_name=category_name)
    group_slug = str(context.get("group_slug") or "")
    category_slug = str(context.get("category_slug") or "")

    schema = schema_for_category(group_slug=group_slug, category_slug=category_slug)
    metadata_key = str(schema.get("metadata_key") or "")
    metadata_payload: dict = {}
    if metadata_key == "vehicle_metadata":
        metadata_payload = dict(vehicle_payload or {})
    elif metadata_key == "energy_metadata":
        metadata_payload = dict(energy_payload or {})
    elif metadata_key == "real_estate_metadata":
        metadata_payload = dict(real_estate_payload or {})

    validated = validate_category_metadata(
        group_slug=group_slug,
        category_slug=category_slug,
        payload=metadata_payload,
    )
    if not validated.get("ok"):
        return (
            False,
            {
                "ok": False,
                "error": "VALIDATION_FAILED",
                "message": "Listing metadata validation failed",
                "details": validated.get("errors") or [],
            },
        )

    listing_type_input = str(listing_type_raw or "").strip().lower()
    listing_type_hint = str(validated.get("listing_type_hint") or "declutter").strip().lower()
    if listing_type_hint in ("vehicle", "energy", "real_estate"):
        final_listing_type = listing_type_hint
    elif listing_type_input:
        final_listing_type = listing_type_input
    else:
        final_listing_type = "declutter"

    vehicle_metadata = validated.get("vehicle_metadata") or {}
    energy_metadata = validated.get("energy_metadata") or {}
    real_estate_metadata = validated.get("real_estate_metadata") or {}
    derived = validated.get("derived") or {}

    listing.listing_type = final_listing_type
    listing.vehicle_metadata = json.dumps(vehicle_metadata, separators=(",", ":")) if vehicle_metadata else None
    listing.energy_metadata = json.dumps(energy_metadata, separators=(",", ":")) if energy_metadata else None
    listing.real_estate_metadata = (
        json.dumps(real_estate_metadata, separators=(",", ":"))
        if real_estate_metadata
        else None
    )

    listing.vehicle_make = str(derived.get("vehicle_make") or "").strip() or None
    listing.vehicle_model = str(derived.get("vehicle_model") or "").strip() or None
    listing.vehicle_year = _maybe_int(derived.get("vehicle_year"))
    listing.battery_type = str(derived.get("battery_type") or "").strip() or None
    listing.inverter_capacity = str(derived.get("inverter_capacity") or "").strip() or None
    listing.lithium_only = bool(derived.get("lithium_only", False))
    listing.bundle_badge = bool(derived.get("bundle_badge", False))
    listing.property_type = str(derived.get("property_type") or "").strip() or None
    listing.bedrooms = _maybe_int(derived.get("bedrooms"))
    listing.bathrooms = _maybe_int(derived.get("bathrooms"))
    listing.toilets = _maybe_int(real_estate_metadata.get("toilets"))
    listing.parking_spaces = _maybe_int(real_estate_metadata.get("parking_spaces"))
    furnished_value = _maybe_bool(derived.get("furnished"))
    listing.furnished = None if furnished_value is None else bool(furnished_value)
    serviced_value = _maybe_bool(derived.get("serviced"))
    listing.serviced = None if serviced_value is None else bool(serviced_value)
    try:
        listing.land_size = (
            float(derived.get("land_size"))
            if derived.get("land_size") not in (None, "")
            else None
        )
    except Exception:
        listing.land_size = None
    listing.title_document_type = str(derived.get("title_document_type") or "").strip() or None
    listing.location_verified = bool(derived.get("location_verified", False))
    listing.inspection_request_enabled = bool(derived.get("inspection_request_enabled", False))
    listing.financing_option = bool(derived.get("financing_option", False))

    delivery_available = _maybe_bool(delivery_available_raw)
    if delivery_available is None:
        delivery_available = _maybe_bool(derived.get("delivery_available"))
    if delivery_available is not None:
        listing.delivery_available = bool(delivery_available)

    inspection_required = _maybe_bool(inspection_required_raw)
    if inspection_required is None:
        inspection_required = _maybe_bool(derived.get("inspection_required"))
    if inspection_required is not None:
        listing.inspection_required = bool(inspection_required)

    if final_listing_type == "vehicle":
        default_status = "approved" if is_admin else "pending"
        listing.approval_status = _normalize_approval_status(approval_status_raw, fallback=default_status)
    else:
        listing.approval_status = _normalize_approval_status(approval_status_raw, fallback="approved")

    return True, None


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
        "merchant_id": int(row.get("merchant_id") or row.get("user_id") or row.get("owner_id") or 0),
        "merchant_name": str(row.get("merchant_name") or row.get("shop_name") or ""),
        "merchant_profile_image_url": str(row.get("merchant_profile_image_url") or row.get("profile_image_url") or ""),
        "title": str(row.get("title") or ""),
        "description": str(row.get("description") or ""),
        "category": str(row.get("category") or ""),
        "category_id": _maybe_int(row.get("category_id")),
        "brand_id": _maybe_int(row.get("brand_id")),
        "model_id": _maybe_int(row.get("model_id")),
        "listing_type": str(row.get("listing_type") or "declutter"),
        "state": str(row.get("state") or ""),
        "city": str(row.get("city") or ""),
        "locality": str(row.get("locality") or ""),
        "condition": str(row.get("condition") or ""),
        "vehicle_metadata": row.get("vehicle_metadata") if isinstance(row.get("vehicle_metadata"), dict) else _parse_json_map(row.get("vehicle_metadata")),
        "energy_metadata": row.get("energy_metadata") if isinstance(row.get("energy_metadata"), dict) else _parse_json_map(row.get("energy_metadata")),
        "real_estate_metadata": row.get("real_estate_metadata") if isinstance(row.get("real_estate_metadata"), dict) else _parse_json_map(row.get("real_estate_metadata")),
        "vehicle_make": str(row.get("vehicle_make") or ""),
        "vehicle_model": str(row.get("vehicle_model") or ""),
        "vehicle_year": _maybe_int(row.get("vehicle_year")),
        "battery_type": str(row.get("battery_type") or ""),
        "inverter_capacity": str(row.get("inverter_capacity") or ""),
        "lithium_only": bool(_maybe_bool(row.get("lithium_only"))),
        "bundle_badge": bool(_maybe_bool(row.get("bundle_badge"))),
        "property_type": str(row.get("property_type") or ""),
        "bedrooms": _maybe_int(row.get("bedrooms")),
        "bathrooms": _maybe_int(row.get("bathrooms")),
        "furnished": bool(_maybe_bool(row.get("furnished"))),
        "serviced": bool(_maybe_bool(row.get("serviced"))),
        "land_size": _maybe_float(row.get("land_size")),
        "title_document_type": str(row.get("title_document_type") or ""),
        "delivery_available": bool(_maybe_bool(row.get("delivery_available"))),
        "inspection_required": bool(_maybe_bool(row.get("inspection_required"))),
        "financing_option": bool(_maybe_bool(row.get("financing_option"))),
        "location_verified": bool(_maybe_bool(row.get("location_verified"))),
        "inspection_request_enabled": bool(_maybe_bool(row.get("inspection_request_enabled"))),
        "approval_status": str(row.get("approval_status") or ""),
        "inspection_flagged": bool(_maybe_bool(row.get("inspection_flagged"))),
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
            "listing_type": bool(supported.get("listing_type", False)),
            "make": bool(supported.get("make", False)),
            "model": bool(supported.get("model", False)),
            "year": bool(supported.get("year", False)),
            "battery_type": bool(supported.get("battery_type", False)),
            "inverter_capacity": bool(supported.get("inverter_capacity", False)),
            "lithium_only": bool(supported.get("lithium_only", False)),
            "property_type": bool(supported.get("property_type", False)),
            "bedrooms": bool(supported.get("bedrooms", False)),
            "bathrooms": bool(supported.get("bathrooms", False)),
            "furnished": bool(supported.get("furnished", False)),
            "serviced": bool(supported.get("serviced", False)),
            "land_size": bool(supported.get("land_size", False)),
            "title_document_type": bool(supported.get("title_document_type", False)),
        },
    }


def _supported_search_filters() -> dict:
    return {
        "delivery_available": hasattr(Listing, "delivery_available"),
        "inspection_required": hasattr(Listing, "inspection_required"),
        "listing_type": hasattr(Listing, "listing_type"),
        "make": hasattr(Listing, "vehicle_make"),
        "model": hasattr(Listing, "vehicle_model"),
        "year": hasattr(Listing, "vehicle_year"),
        "battery_type": hasattr(Listing, "battery_type"),
        "inverter_capacity": hasattr(Listing, "inverter_capacity"),
        "lithium_only": hasattr(Listing, "lithium_only"),
        "property_type": hasattr(Listing, "property_type"),
        "bedrooms": hasattr(Listing, "bedrooms"),
        "bathrooms": hasattr(Listing, "bathrooms"),
        "furnished": hasattr(Listing, "furnished"),
        "serviced": hasattr(Listing, "serviced"),
        "land_size": hasattr(Listing, "land_size"),
        "title_document_type": hasattr(Listing, "title_document_type"),
    }


def _normalized_sort_key(raw_sort: str) -> str:
    candidate = str(raw_sort or "relevance").strip().lower()
    if candidate in ("price_low", "price_low_to_high", "priceasc"):
        return "price_asc"
    if candidate in ("price_high", "price_high_to_low", "pricedesc"):
        return "price_desc"
    if candidate in ("new", "latest"):
        return "newest"
    if candidate in ("relevance", "newest", "price_asc", "price_desc"):
        return candidate
    return "relevance"


def _meili_quote(raw_value) -> str:
    return json.dumps(str(raw_value or ""))


def _meili_number(raw_value) -> str:
    try:
        value = float(raw_value)
    except Exception:
        return "0"
    whole = int(value)
    if abs(value - float(whole)) < 1e-9:
        return str(whole)
    return f"{value:.6f}".rstrip("0").rstrip(".")


def _meili_filter_expression(args: dict, *, include_inactive: bool) -> str | None:
    clauses: list[str] = []
    if not include_inactive:
        clauses.append("is_active = true")
        clauses.append(f"(listing_type != {_meili_quote('vehicle')} OR approval_status = {_meili_quote('approved')})")

    category = str(args.get("category") or "").strip()
    if category:
        clauses.append(f"category_ci = {_meili_quote(category.lower())}")
    category_id = _maybe_int(args.get("category_id"))
    parent_category_id = _maybe_int(args.get("parent_category_id"))
    if category_id is not None:
        clauses.append(f"category_id = {int(category_id)}")
    elif parent_category_id is not None:
        descendant_ids = _descendant_category_ids(int(parent_category_id))
        if descendant_ids:
            clauses.append(f"category_id IN [{','.join(str(int(x)) for x in descendant_ids)}]")

    brand_id = _maybe_int(args.get("brand_id"))
    if brand_id is not None:
        clauses.append(f"brand_id = {int(brand_id)}")
    model_id = _maybe_int(args.get("model_id"))
    if model_id is not None:
        clauses.append(f"model_id = {int(model_id)}")

    listing_type = str(args.get("listing_type") or "").strip().lower()
    if listing_type:
        clauses.append(f"listing_type = {_meili_quote(listing_type)}")

    make = str(args.get("make") or "").strip()
    if make:
        clauses.append(f"make_ci = {_meili_quote(make.lower())}")
    model = str(args.get("model") or "").strip()
    if model:
        clauses.append(f"model_ci = {_meili_quote(model.lower())}")
    year = _maybe_int(args.get("year"))
    if year is not None:
        clauses.append(f"year = {int(year)}")

    battery_type = str(args.get("battery_type") or "").strip()
    if battery_type:
        clauses.append(f"battery_type_ci = {_meili_quote(battery_type.lower())}")
    inverter_capacity = str(args.get("inverter_capacity") or "").strip()
    if inverter_capacity:
        clauses.append(f"inverter_capacity_ci = {_meili_quote(inverter_capacity.lower())}")
    lithium_only = _maybe_bool(args.get("lithium_only"))
    if lithium_only is not None:
        clauses.append(f"lithium_only = {'true' if bool(lithium_only) else 'false'}")

    property_type = str(args.get("property_type") or "").strip()
    if property_type:
        clauses.append(f"property_type_ci = {_meili_quote(property_type.lower())}")
    bedrooms_min = _maybe_int(args.get("bedrooms_min"))
    if bedrooms_min is not None:
        clauses.append(f"bedrooms >= {int(bedrooms_min)}")
    bedrooms_max = _maybe_int(args.get("bedrooms_max"))
    if bedrooms_max is not None:
        clauses.append(f"bedrooms <= {int(bedrooms_max)}")
    bathrooms_min = _maybe_int(args.get("bathrooms_min"))
    if bathrooms_min is not None:
        clauses.append(f"bathrooms >= {int(bathrooms_min)}")
    bathrooms_max = _maybe_int(args.get("bathrooms_max"))
    if bathrooms_max is not None:
        clauses.append(f"bathrooms <= {int(bathrooms_max)}")

    furnished = _maybe_bool(args.get("furnished"))
    if furnished is not None:
        clauses.append(f"furnished = {'true' if bool(furnished) else 'false'}")
    serviced = _maybe_bool(args.get("serviced"))
    if serviced is not None:
        clauses.append(f"serviced = {'true' if bool(serviced) else 'false'}")

    land_size_min = _maybe_float(args.get("land_size_min"))
    if land_size_min is not None:
        clauses.append(f"land_size >= {_meili_number(land_size_min)}")
    land_size_max = _maybe_float(args.get("land_size_max"))
    if land_size_max is not None:
        clauses.append(f"land_size <= {_meili_number(land_size_max)}")

    title_document_type = str(args.get("title_document_type") or "").strip()
    if title_document_type:
        clauses.append(f"title_document_type_ci = {_meili_quote(title_document_type.lower())}")

    city = str(args.get("city") or "").strip()
    if city:
        clauses.append(f"city_ci = {_meili_quote(city.lower())}")
    area = str(args.get("area") or "").strip()
    if area:
        clauses.append(f"locality_ci = {_meili_quote(area.lower())}")
    state = str(args.get("state") or "").strip()
    if state:
        clauses.append(f"state_ci = {_meili_quote(state.lower())}")

    condition = str(args.get("condition") or "").strip()
    if condition:
        clauses.append(f"condition_ci = {_meili_quote(condition.lower())}")

    status_key = str(args.get("status") or "").strip().lower()
    if status_key and status_key not in ("all", "any"):
        if status_key in ("active", "inactive"):
            clauses.append(f"is_active = {'true' if status_key == 'active' else 'false'}")
        else:
            clauses.append(f"status_ci = {_meili_quote(status_key)}")

    delivery_available = _maybe_bool(args.get("delivery_available"))
    if delivery_available is not None:
        clauses.append(f"delivery_available = {'true' if bool(delivery_available) else 'false'}")
    inspection_required = _maybe_bool(args.get("inspection_required"))
    if inspection_required is not None:
        clauses.append(f"inspection_required = {'true' if bool(inspection_required) else 'false'}")

    min_price = _maybe_float(args.get("min_price"))
    if min_price is not None:
        clauses.append(f"price >= {_meili_number(min_price)}")
    max_price = _maybe_float(args.get("max_price"))
    if max_price is not None:
        clauses.append(f"price <= {_meili_number(max_price)}")

    if not clauses:
        return None
    return " AND ".join(clauses)


def _meili_sort_for_search(sort_key: str, *, q: str) -> list[str] | None:
    if sort_key == "price_asc":
        return ["price:asc"]
    if sort_key == "price_desc":
        return ["price:desc"]
    if sort_key == "newest":
        return ["created_at:desc"]
    if sort_key == "relevance" and not str(q or "").strip():
        return ["created_at:desc"]
    return None


def _run_sql_search(args: dict, *, include_inactive: bool, preferred_city: str = "", preferred_state: str = "") -> dict:
    return search_listings_v2(
        q=args["q"],
        category=args["category"],
        category_id=args["category_id"],
        parent_category_id=args["parent_category_id"],
        brand_id=args["brand_id"],
        model_id=args["model_id"],
        listing_type=args["listing_type"],
        make=args["make"],
        model=args["model"],
        year=args["year"],
        battery_type=args["battery_type"],
        inverter_capacity=args["inverter_capacity"],
        lithium_only=args["lithium_only"],
        property_type=args["property_type"],
        bedrooms_min=args["bedrooms_min"],
        bedrooms_max=args["bedrooms_max"],
        bathrooms_min=args["bathrooms_min"],
        bathrooms_max=args["bathrooms_max"],
        furnished=args["furnished"],
        serviced=args["serviced"],
        land_size_min=args["land_size_min"],
        land_size_max=args["land_size_max"],
        title_document_type=args["title_document_type"],
        city=args["city"],
        area=args["area"],
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
        include_inactive=bool(include_inactive),
        preferred_city=preferred_city,
        preferred_state=preferred_state,
    )


def _run_meili_search(args: dict, *, include_inactive: bool) -> dict:
    client = get_meili_client()
    sort_key = _normalized_sort_key(str(args.get("sort") or "relevance"))
    result = client.search(
        listings_index_name(),
        str(args.get("q") or "").strip(),
        _meili_filter_expression(args, include_inactive=bool(include_inactive)),
        _meili_sort_for_search(sort_key, q=str(args.get("q") or "")),
        int(args.get("limit") or 20),
        int(args.get("offset") or 0),
    )
    hits = result.get("hits")
    if not isinstance(hits, list):
        hits = []
    total = (
        _maybe_int(result.get("estimatedTotalHits"))
        or _maybe_int(result.get("totalHits"))
        or len(hits)
    )
    return {
        "ok": True,
        "items": [dict(hit) for hit in hits if isinstance(hit, dict)],
        "total": int(total),
        "limit": int(args.get("limit") or 20),
        "offset": int(args.get("offset") or 0),
        "sort": sort_key,
        "q": str(args.get("q") or ""),
        "supported_filters": _supported_search_filters(),
    }


def _enqueue_search_index(listing_id: int) -> None:
    if not search_engine_is_meili():
        return
    try:
        from app.tasks.search_tasks import search_index_listing

        search_index_listing.delay(int(listing_id), trace_id=get_request_id())
    except Exception:
        try:
            current_app.logger.exception("search_index_enqueue_failed listing_id=%s", int(listing_id))
        except Exception:
            pass


def _enqueue_search_delete(listing_id: int) -> None:
    if not search_engine_is_meili():
        return
    try:
        from app.tasks.search_tasks import search_delete_listing

        search_delete_listing.delay(int(listing_id), trace_id=get_request_id())
    except Exception:
        try:
            current_app.logger.exception("search_delete_enqueue_failed listing_id=%s", int(listing_id))
        except Exception:
            pass


def _listing_detail_cache_key(listing_id: int) -> str:
    return build_cache_key("listing_detail", {"id": int(listing_id)})


def _feed_response_cache_key(scope: str, params: dict) -> str:
    return build_cache_key(f"feed:{scope}", params)


def _invalidate_listing_read_caches(listing_id: int | None = None) -> None:
    # Writes are much less frequent than reads; broad feed invalidation is acceptable.
    try:
        if listing_id is not None:
            delete(_listing_detail_cache_key(int(listing_id)))
    except Exception:
        pass
    try:
        delete_prefix("v1:feed:")
    except Exception:
        pass


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


def _is_phone_verified(u: User | None) -> bool:
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
        platform_fee = round(base * 0.05, 2)
        final_price = round(base + platform_fee, 2)

    try:
        listing.base_price = float(base)
        listing.platform_fee = float(platform_fee)
        listing.final_price = float(final_price)
    except Exception:
        pass
    listing.price = float(final_price)


def _listing_description_blocked(description: str) -> bool:
    return contains_prohibited_listing_description(description or "")


_CUSTOMER_PAYOUT_FIELDS = (
    "customer_full_name",
    "customer_address",
    "customer_phone",
    "bank_name",
    "bank_account_number",
    "bank_account_name",
)


def _normalize_customer_payout_profile(
    raw_value,
    *,
    fallback: dict | None = None,
    required: bool,
) -> tuple[bool, dict | None, dict | None]:
    payload = _parse_json_map(raw_value)
    fallback_map = dict(fallback or {})
    for key in _CUSTOMER_PAYOUT_FIELDS:
        if not payload.get(key):
            fallback_val = fallback_map.get(key)
            if fallback_val not in (None, ""):
                payload[key] = fallback_val

    if not payload and not required:
        return True, None, None

    profile: dict[str, str] = {}
    missing: list[str] = []
    for key in _CUSTOMER_PAYOUT_FIELDS:
        value = str(payload.get(key) or "").strip()
        if not value:
            missing.append(key)
        else:
            profile[key] = value

    if required and missing:
        return (
            False,
            None,
            {
                "ok": False,
                "error": "CUSTOMER_PAYOUT_PROFILE_REQUIRED",
                "message": "Merchant listings require complete customer payout details.",
                "details": [f"{key} is required" for key in missing],
            },
        )

    account_number = str(profile.get("bank_account_number") or "").strip().replace(" ", "")
    if account_number and not account_number.isdigit():
        return (
            False,
            None,
            {
                "ok": False,
                "error": "CUSTOMER_PAYOUT_PROFILE_INVALID",
                "message": "Customer bank account number must contain digits only.",
            },
        )
    if account_number:
        profile["bank_account_number"] = account_number

    return True, profile, None

@market_bp.get("/locations/popular")
def popular_locations():
    """Top locations by listing count for marketplace discovery and filters."""
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


def _category_tree_payload() -> list[dict]:
    rows = (
        Category.query.filter(Category.is_active.is_(True))
        .order_by(Category.parent_id.asc(), Category.sort_order.asc(), Category.name.asc())
        .all()
    )
    items_by_id: dict[int, dict] = {}
    roots: list[dict] = []
    for row in rows:
        node = row.to_dict()
        node["children"] = []
        items_by_id[int(row.id)] = node
    for row in rows:
        node = items_by_id.get(int(row.id))
        if node is None:
            continue
        if row.parent_id is None:
            roots.append(node)
        else:
            parent = items_by_id.get(int(row.parent_id))
            if parent is not None:
                parent.setdefault("children", []).append(node)
            else:
                roots.append(node)
    return roots


@market_bp.get("/public/categories")
def public_categories():
    try:
        items = _category_tree_payload()
        return jsonify({"ok": True, "items": items, "category_groups": CATEGORY_GROUPS}), 200
    except Exception as exc:
        try:
            db.session.rollback()
        except Exception:
            pass
        return jsonify({"ok": False, "error": "CATEGORIES_READ_FAILED", "message": str(exc), "items": []}), 500


@market_bp.get("/public/categories/form-schema")
def public_category_form_schema():
    category_id = _maybe_int(request.args.get("category_id"))
    category = (request.args.get("category") or "").strip()
    try:
        payload = _category_schema_payload(category_id=category_id, category_name=category)
        payload["category_groups"] = CATEGORY_GROUPS
        return jsonify(payload), 200
    except Exception as exc:
        try:
            db.session.rollback()
        except Exception:
            pass
        return jsonify({"ok": False, "error": "CATEGORY_SCHEMA_READ_FAILED", "message": str(exc)}), 500


@market_bp.get("/public/category-groups")
def public_category_groups():
    return jsonify({"ok": True, "items": CATEGORY_GROUPS}), 200


@market_bp.get("/public/filters")
def public_filters():
    category_id = _maybe_int(request.args.get("category_id"))
    brand_id = _maybe_int(request.args.get("brand_id"))
    try:
        brands_q = Brand.query.filter(Brand.is_active.is_(True))
        if category_id is not None:
            brands_q = brands_q.filter(
                or_(
                    Brand.category_id == int(category_id),
                    Brand.category_id.is_(None),
                )
            )
        brands = [row.to_dict() for row in brands_q.order_by(Brand.sort_order.asc(), Brand.name.asc()).all()]

        models_q = BrandModel.query.filter(BrandModel.is_active.is_(True))
        if category_id is not None:
            models_q = models_q.filter(
                or_(
                    BrandModel.category_id == int(category_id),
                    BrandModel.category_id.is_(None),
                )
            )
        if brand_id is not None:
            models_q = models_q.filter(BrandModel.brand_id == int(brand_id))
        models = [row.to_dict() for row in models_q.order_by(BrandModel.sort_order.asc(), BrandModel.name.asc()).all()]
        return jsonify({"ok": True, "brands": brands, "models": models}), 200
    except Exception as exc:
        try:
            db.session.rollback()
        except Exception:
            pass
        return jsonify({"ok": False, "error": "FILTERS_READ_FAILED", "message": str(exc), "brands": [], "models": []}), 500


def _normalize_saved_search_vertical(value: str) -> str:
    raw = str(value or "").strip().lower()
    allowed = {"vehicles", "energy", "real_estate", "marketplace"}
    return raw if raw in allowed else "marketplace"


@market_bp.get("/saved-searches")
def list_saved_searches():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    vertical = _normalize_saved_search_vertical(request.args.get("vertical") or "")
    query = SavedSearch.query.filter(SavedSearch.user_id == int(u.id))
    if vertical != "marketplace":
        query = query.filter(SavedSearch.vertical == vertical)
    rows = query.order_by(SavedSearch.last_used_at.desc(), SavedSearch.created_at.desc()).limit(100).all()
    return jsonify({"ok": True, "items": [row.to_dict() for row in rows]}), 200


@market_bp.post("/saved-searches")
def create_saved_search():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    query_map = payload.get("query_json")
    if not isinstance(query_map, dict):
        query_map = _parse_json_map(query_map)
    if not isinstance(query_map, dict):
        query_map = {}
    name = str(payload.get("name") or "").strip()
    if not name:
        name = "Saved search"
    vertical = _normalize_saved_search_vertical(payload.get("vertical") or query_map.get("vertical") or "")
    count = SavedSearch.query.filter(SavedSearch.user_id == int(u.id)).count()
    if count >= 20:
        return jsonify({"ok": False, "error": "SAVED_SEARCH_LIMIT_REACHED", "message": "You can save up to 20 searches."}), 400
    row = SavedSearch(
        user_id=int(u.id),
        vertical=vertical,
        name=name[:120],
        query_json=json.dumps(query_map, separators=(",", ":")),
        last_used_at=datetime.utcnow(),
    )
    try:
        db.session.add(row)
        db.session.commit()
        return jsonify({"ok": True, "item": row.to_dict()}), 201
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "SAVED_SEARCH_CREATE_FAILED", "message": str(exc)}), 500


@market_bp.put("/saved-searches/<int:search_id>")
def update_saved_search(search_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    row = SavedSearch.query.get(int(search_id))
    if not row or int(row.user_id) != int(u.id):
        return jsonify({"message": "Not found"}), 404
    payload = request.get_json(silent=True) or {}
    if "name" in payload:
        row.name = str(payload.get("name") or "").strip()[:120] or row.name
    if "vertical" in payload:
        row.vertical = _normalize_saved_search_vertical(payload.get("vertical") or "")
    if "query_json" in payload:
        query_map = payload.get("query_json")
        if not isinstance(query_map, dict):
            query_map = _parse_json_map(query_map)
        row.query_json = json.dumps(dict(query_map or {}), separators=(",", ":"))
    if bool(payload.get("touch_last_used")):
        row.last_used_at = datetime.utcnow()
    row.updated_at = datetime.utcnow()
    try:
        db.session.add(row)
        db.session.commit()
        return jsonify({"ok": True, "item": row.to_dict()}), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "SAVED_SEARCH_UPDATE_FAILED", "message": str(exc)}), 500


@market_bp.post("/saved-searches/<int:search_id>/use")
def use_saved_search(search_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    row = SavedSearch.query.get(int(search_id))
    if not row or int(row.user_id) != int(u.id):
        return jsonify({"message": "Not found"}), 404
    row.last_used_at = datetime.utcnow()
    row.updated_at = datetime.utcnow()
    try:
        db.session.add(row)
        db.session.commit()
        return jsonify({"ok": True, "item": row.to_dict()}), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "SAVED_SEARCH_USE_FAILED", "message": str(exc)}), 500


@market_bp.delete("/saved-searches/<int:search_id>")
def delete_saved_search(search_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    row = SavedSearch.query.get(int(search_id))
    if not row or int(row.user_id) != int(u.id):
        return jsonify({"message": "Not found"}), 404
    try:
        db.session.delete(row)
        db.session.commit()
        return jsonify({"ok": True, "deleted": True, "id": int(search_id)}), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "SAVED_SEARCH_DELETE_FAILED", "message": str(exc)}), 500


@market_bp.get("/admin/images/fingerprints")
def admin_image_fingerprints():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    q = (request.args.get("q") or "").strip().lower()
    try:
        limit = max(1, min(int(request.args.get("limit") or 50), 200))
    except Exception:
        limit = 50
    try:
        offset = max(0, int(request.args.get("offset") or 0))
    except Exception:
        offset = 0

    query = ImageFingerprint.query
    if q:
        like = f"%{q}%"
        query = query.filter(
            or_(
                ImageFingerprint.hash_hex.ilike(like),
                ImageFingerprint.image_url.ilike(like),
                ImageFingerprint.cloudinary_public_id.ilike(like),
            )
        )
    total = query.count()
    rows = query.order_by(ImageFingerprint.created_at.desc(), ImageFingerprint.id.desc()).offset(offset).limit(limit).all()
    items = [
        {
            "id": int(row.id),
            "created_at": row.created_at.isoformat() if row.created_at else None,
            "hash_type": row.hash_type or "phash64",
            "hash_hex": row.hash_hex or "",
            "source": row.source or "",
            "image_url": row.image_url or "",
            "cloudinary_public_id": row.cloudinary_public_id or "",
            "listing_id": int(row.listing_id) if row.listing_id is not None else None,
            "shortlet_id": int(row.shortlet_id) if row.shortlet_id is not None else None,
            "uploader_user_id": int(row.uploader_user_id) if row.uploader_user_id is not None else None,
        }
        for row in rows
    ]
    return jsonify({"ok": True, "items": items, "total": int(total), "limit": int(limit), "offset": int(offset)}), 200


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
    cache_key = _feed_response_cache_key(
        "public_listings_search",
        {
            **args,
            "preferred_city": pref_city,
            "preferred_state": pref_state,
        },
    )
    cached_payload = get_json(cache_key)
    if isinstance(cached_payload, dict):
        return jsonify(cached_payload), 200
    try:
        raw_payload = _run_sql_search(
            args,
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
        set_json(cache_key, payload, ttl_seconds=feed_cache_ttl_seconds())
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


@market_bp.get("/listings/search")
def listings_search():
    args = _search_args()
    u = _current_user()
    pref_city = (request.args.get("city") or "").strip()
    pref_state = (request.args.get("state") or "").strip()
    if not pref_city and not pref_state:
        user_city, user_state = _user_preferences(u)
        pref_city = user_city or pref_city
        pref_state = user_state or pref_state
    include_inactive = _is_admin(u)
    cache_key = _feed_response_cache_key(
        "listings_search",
        {
            **args,
            "preferred_city": pref_city,
            "preferred_state": pref_state,
            "include_inactive": bool(include_inactive),
            "requester_user_id": int(getattr(u, "id", 0) or 0),
            "search_engine": "meili" if bool(search_engine_is_meili() and not include_inactive) else "sql",
        },
    )
    cached_payload = get_json(cache_key)
    if isinstance(cached_payload, dict):
        return jsonify(cached_payload), 200
    try:
        raw_payload: dict
        use_meili = bool(search_engine_is_meili() and not include_inactive)
        if use_meili:
            raw_payload = _run_meili_search(args, include_inactive=include_inactive)
        else:
            raw_payload = _run_sql_search(
                args,
                include_inactive=include_inactive,
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
        set_json(cache_key, payload, ttl_seconds=feed_cache_ttl_seconds())
        return jsonify(payload), 200
    except SearchNotInitialized:
        if search_fallback_sql_enabled():
            try:
                raw_payload = _run_sql_search(
                    args,
                    include_inactive=include_inactive,
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
                set_json(cache_key, payload, ttl_seconds=feed_cache_ttl_seconds())
                return jsonify(payload), 200
            except Exception:
                try:
                    db.session.rollback()
                except Exception:
                    pass
        return jsonify(
            {
                "ok": False,
                "error": "SEARCH_NOT_INITIALIZED",
                "message": "Search index is not initialized. Run /api/admin/search/init.",
                "trace_id": get_request_id(),
            }
        ), 400
    except SearchUnavailable:
        if search_fallback_sql_enabled():
            try:
                raw_payload = _run_sql_search(
                    args,
                    include_inactive=include_inactive,
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
                set_json(cache_key, payload, ttl_seconds=feed_cache_ttl_seconds())
                return jsonify(payload), 200
            except Exception:
                try:
                    db.session.rollback()
                except Exception:
                    pass
        return jsonify(
            {
                "ok": False,
                "error": {
                    "code": "SEARCH_UNAVAILABLE",
                    "message": "Search service unavailable. Try again shortly.",
                },
                "trace_id": get_request_id(),
            }
        ), 503
    except Exception:
        try:
            db.session.rollback()
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
        raw_payload = _run_sql_search(
            args,
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


@market_bp.post("/admin/listings/<int:listing_id>/approve")
def admin_approve_listing(listing_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    listing = Listing.query.get(int(listing_id))
    if not listing:
        return jsonify({"message": "Not found"}), 404

    payload = request.get_json(silent=True) or {}
    status_raw = str(payload.get("status") or "").strip().lower()
    approved_raw = _maybe_bool(payload.get("approved"))
    if status_raw in ("approved", "pending", "rejected"):
        status = status_raw
    elif approved_raw is True:
        status = "approved"
    elif approved_raw is False:
        status = "rejected"
    else:
        status = "approved"

    listing.approval_status = status
    if status == "approved" and hasattr(listing, "is_active"):
        listing.is_active = True
    try:
        db.session.add(listing)
        db.session.commit()
        _invalidate_listing_read_caches(int(listing.id))
        _enqueue_search_index(int(listing.id))
        return jsonify({"ok": True, "listing": listing.to_dict(base_url=_base_url())}), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "LISTING_APPROVAL_FAILED", "message": str(exc)}), 500


@market_bp.post("/admin/listings/<int:listing_id>/inspection-flag")
def admin_flag_listing_for_inspection(listing_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    listing = Listing.query.get(int(listing_id))
    if not listing:
        return jsonify({"message": "Not found"}), 404

    payload = request.get_json(silent=True) or {}
    flagged = _maybe_bool(payload.get("flagged"))
    if flagged is None:
        flagged = True
    listing.inspection_flagged = bool(flagged)
    if bool(flagged):
        listing.inspection_required = True
    try:
        db.session.add(listing)
        db.session.commit()
        _invalidate_listing_read_caches(int(listing.id))
        _enqueue_search_index(int(listing.id))
        return jsonify({"ok": True, "listing": listing.to_dict(base_url=_base_url())}), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "LISTING_INSPECTION_FLAG_FAILED", "message": str(exc)}), 500


@market_bp.get("/admin/listings/<int:listing_id>/customer-payout-profile")
def admin_listing_customer_payout_profile(listing_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    listing = Listing.query.get(int(listing_id))
    if not listing:
        return jsonify({"message": "Not found"}), 404
    profile = _parse_json_map(getattr(listing, "customer_payout_profile_json", None))
    if not profile:
        return jsonify({"ok": False, "error": "CUSTOMER_PAYOUT_PROFILE_NOT_FOUND", "message": "No customer payout profile found for this listing."}), 404
    copy_text = (
        f"Customer: {profile.get('customer_full_name', '')}\n"
        f"Phone: {profile.get('customer_phone', '')}\n"
        f"Bank: {profile.get('bank_name', '')}\n"
        f"Account Number: {profile.get('bank_account_number', '')}\n"
        f"Account Name: {profile.get('bank_account_name', '')}"
    )
    try:
        db.session.add(
            AuditLog(
                actor_user_id=int(u.id),
                action="admin_view_customer_payout_profile",
                target_type="listing",
                target_id=int(listing.id),
                meta=json.dumps(
                    {
                        "listing_id": int(listing.id),
                        "customer_full_name": str(profile.get("customer_full_name") or ""),
                    },
                    separators=(",", ":"),
                ),
            )
        )
        db.session.commit()
    except Exception:
        db.session.rollback()
    return jsonify(
        {
            "ok": True,
            "listing_id": int(listing.id),
            "customer_payout_profile": profile,
            "copy_text": copy_text,
            "customer_profile_updated_at": (
                listing.customer_profile_updated_at.isoformat()
                if getattr(listing, "customer_profile_updated_at", None)
                else None
            ),
            "customer_profile_updated_by": (
                int(listing.customer_profile_updated_by)
                if getattr(listing, "customer_profile_updated_by", None) is not None
                else None
            ),
        }
    ), 200


@market_bp.get("/public/listings/recommended")
def public_listings_recommended():
    limit_raw = request.args.get("limit") or "20"
    try:
        limit = max(1, min(int(limit_raw), 60))
    except Exception:
        limit = 20
    city = (request.args.get("city") or "").strip()
    state = (request.args.get("state") or "").strip()
    category_id = _maybe_int(request.args.get("category_id"))
    parent_category_id = _maybe_int(request.args.get("parent_category_id"))
    brand_id = _maybe_int(request.args.get("brand_id"))
    model_id = _maybe_int(request.args.get("model_id"))
    u = _current_user()
    if not city and not state:
        pref_city, pref_state = _user_preferences(u)
        city = pref_city or city
        state = pref_state or state
    cache_key = _feed_response_cache_key(
        "public_listings_recommended",
        {
            "limit": int(limit),
            "city": city,
            "state": state,
            "category_id": category_id,
            "parent_category_id": parent_category_id,
            "brand_id": brand_id,
            "model_id": model_id,
        },
    )
    cached_payload = get_json(cache_key)
    if isinstance(cached_payload, dict):
        return jsonify(cached_payload), 200
    try:
        q = _apply_listing_ordering(_apply_listing_active_filter(Listing.query))
        if category_id is not None and hasattr(Listing, "category_id"):
            q = q.filter(Listing.category_id == int(category_id))
        elif parent_category_id is not None and hasattr(Listing, "category_id"):
            descendant_ids = _descendant_category_ids(int(parent_category_id))
            if descendant_ids:
                q = q.filter(Listing.category_id.in_(descendant_ids))
        if brand_id is not None and hasattr(Listing, "brand_id"):
            q = q.filter(Listing.brand_id == int(brand_id))
        if model_id is not None and hasattr(Listing, "model_id"):
            q = q.filter(Listing.model_id == int(model_id))
        rows = q.limit(500).all()
        ranked = []
        for row in rows:
            score, reasons = ranking_for_listing(row, preferred_city=city, preferred_state=state)
            payload = _listing_item_from_raw(row.to_dict(base_url=_base_url()), ranking_score=int(score), ranking_reason=reasons)
            ranked.append(payload)
        ranked.sort(key=lambda item: (int(item.get("ranking_score", 0)), item.get("created_at") or ""), reverse=True)
        out = {"ok": True, "city": city, "state": state, "items": ranked[:limit], "limit": limit}
        set_json(cache_key, out, ttl_seconds=feed_cache_ttl_seconds())
        return jsonify(out), 200
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        return jsonify({"ok": True, "city": city, "state": state, "items": [], "limit": limit}), 200


def _public_discovery_args() -> dict:
    try:
        limit = max(1, min(int(request.args.get("limit") or 20), 60))
    except Exception:
        limit = 20
    try:
        offset = max(0, int(request.args.get("offset") or 0))
    except Exception:
        offset = 0
    return {
        "limit": limit,
        "offset": offset,
        "city": (request.args.get("city") or "").strip(),
        "state": (request.args.get("state") or "").strip(),
        "category_id": _maybe_int(request.args.get("category_id")),
        "parent_category_id": _maybe_int(request.args.get("parent_category_id")),
        "brand_id": _maybe_int(request.args.get("brand_id")),
        "model_id": _maybe_int(request.args.get("model_id")),
    }


def _discovery_query_with_taxonomy(
    *,
    category_id: int | None,
    parent_category_id: int | None,
    brand_id: int | None,
    model_id: int | None,
):
    q = _apply_listing_ordering(_apply_listing_active_filter(Listing.query))
    if category_id is not None and hasattr(Listing, "category_id"):
        q = q.filter(Listing.category_id == int(category_id))
    elif parent_category_id is not None and hasattr(Listing, "category_id"):
        descendant_ids = _descendant_category_ids(int(parent_category_id))
        if descendant_ids:
            q = q.filter(Listing.category_id.in_(descendant_ids))
    if brand_id is not None and hasattr(Listing, "brand_id"):
        q = q.filter(Listing.brand_id == int(brand_id))
    if model_id is not None and hasattr(Listing, "model_id"):
        q = q.filter(Listing.model_id == int(model_id))
    return q


@market_bp.get("/public/listings/new_drops")
def public_listings_new_drops():
    args = _public_discovery_args()
    city = args["city"]
    state = args["state"]
    u = _current_user()
    if not city and not state:
        pref_city, pref_state = _user_preferences(u)
        city = pref_city or city
        state = pref_state or state
    try:
        q = _discovery_query_with_taxonomy(
            category_id=args["category_id"],
            parent_category_id=args["parent_category_id"],
            brand_id=args["brand_id"],
            model_id=args["model_id"],
        )
        q = q.order_by(Listing.created_at.desc(), Listing.id.desc())
        total = q.count()
        rows = q.offset(int(args["offset"])).limit(int(args["limit"])).all()
        items = []
        for row in rows:
            score, reasons = ranking_for_listing(row, preferred_city=city, preferred_state=state)
            payload = _listing_item_from_raw(
                row.to_dict(base_url=_base_url()),
                ranking_score=int(score),
                ranking_reason=reasons,
            )
            items.append(payload)
        return jsonify(
            {
                "ok": True,
                "city": city,
                "state": state,
                "items": items,
                "limit": int(args["limit"]),
                "offset": int(args["offset"]),
                "total": int(total),
            }
        ), 200
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        return jsonify(
            {
                "ok": True,
                "city": city,
                "state": state,
                "items": [],
                "limit": int(args["limit"]),
                "offset": int(args["offset"]),
                "total": 0,
            }
        ), 200


@market_bp.get("/public/listings/deals")
def public_listings_deals():
    args = _public_discovery_args()
    city = args["city"]
    state = args["state"]
    u = _current_user()
    if not city and not state:
        pref_city, pref_state = _user_preferences(u)
        city = pref_city or city
        state = pref_state or state
    try:
        q = _discovery_query_with_taxonomy(
            category_id=args["category_id"],
            parent_category_id=args["parent_category_id"],
            brand_id=args["brand_id"],
            model_id=args["model_id"],
        )
        q = q.order_by(Listing.heat_score.desc(), Listing.price.asc(), Listing.created_at.desc(), Listing.id.desc())
        total = q.count()
        rows = q.offset(int(args["offset"])).limit(int(args["limit"])).all()
        items = []
        for row in rows:
            score, reasons = ranking_for_listing(row, preferred_city=city, preferred_state=state)
            payload = _listing_item_from_raw(
                row.to_dict(base_url=_base_url()),
                ranking_score=int(score),
                ranking_reason=reasons,
            )
            items.append(payload)
        return jsonify(
            {
                "ok": True,
                "city": city,
                "state": state,
                "items": items,
                "limit": int(args["limit"]),
                "offset": int(args["offset"]),
                "total": int(total),
            }
        ), 200
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        return jsonify(
            {
                "ok": True,
                "city": city,
                "state": state,
                "items": [],
                "limit": int(args["limit"]),
                "offset": int(args["offset"]),
                "total": 0,
            }
        ), 200


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
    """Simple heatmap data for discovery views.
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
    """Heat buckets for map-style summaries (state/city counts)."""
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
    """Quick fee quote endpoint for listing and marketplace UI."""
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
        platform_fee = round(base_price * 0.05, 2)
        final_price = round(base_price + platform_fee, 2)
        rule = "shortlet_addon_5pct"
    elif seller_role == "merchant":
        platform_fee = round(base_price * 0.05, 2)
        final_price = round(base_price + platform_fee, 2)
        rule = "merchant_addon_5pct"
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
    u = _current_user()
    cache_key = _listing_detail_cache_key(int(listing_id))
    cached_envelope = get_json(cache_key)
    if isinstance(cached_envelope, dict):
        cached_listing = cached_envelope.get("listing") if isinstance(cached_envelope.get("listing"), dict) else None
        if isinstance(cached_listing, dict):
            is_owner_cached = False
            try:
                is_owner_cached = bool(u is not None and int(getattr(u, "id", 0) or 0) == int(cached_listing.get("user_id") or 0))
            except Exception:
                is_owner_cached = False
            if not _is_admin(u) and not is_owner_cached:
                return jsonify(cached_envelope), 200
    item = Listing.query.get(listing_id)
    if not item:
        return jsonify({"message": "Not found"}), 404
    include_private = bool(_is_admin(u) or _is_owner(u, item))
    payload = item.to_dict(base_url=_base_url(), include_private=include_private)
    seller_id = _maybe_int(payload.get("user_id")) or _maybe_int(payload.get("owner_id"))
    if seller_id:
        merchant = MerchantProfile.query.filter_by(user_id=int(seller_id)).first()
        user = User.query.get(int(seller_id))
        if merchant and (merchant.shop_name or "").strip():
            payload["merchant_name"] = (merchant.shop_name or "").strip()
        elif user and (user.name or "").strip():
            payload["merchant_name"] = (user.name or "").strip()
        payload["merchant_profile_image_url"] = (getattr(user, "profile_image_url", "") or "") if user else ""
    envelope = {"ok": True, "listing": payload}
    if not include_private:
        set_json(cache_key, envelope, ttl_seconds=listing_detail_cache_ttl_seconds())
    return jsonify(envelope), 200


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

    if not bool(request.is_json):
        return jsonify({"ok": False, "error": "INVALID_JSON", "message": "Request body must be valid JSON."}), 400
    try:
        payload = request.get_json(silent=False)
    except BadRequest:
        return jsonify({"ok": False, "error": "INVALID_JSON", "message": "Malformed JSON payload."}), 400
    except Exception:
        return jsonify({"ok": False, "error": "INVALID_JSON", "message": "Invalid JSON payload."}), 400
    if not isinstance(payload, dict):
        return jsonify({"ok": False, "error": "INVALID_JSON", "message": "JSON payload must be an object."}), 400
    if not payload:
        return jsonify({"ok": False, "error": "EMPTY_UPDATE", "message": "Update payload cannot be empty."}), 400

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
        next_listing_type = str(payload.get("listing_type") or getattr(item, "listing_type", "declutter") or "declutter")
        ok, info = enforce_listing_cap(int(u.id), account_role, next_listing_type)
        if not ok:
            return jsonify(info), 403
    if "title" in payload:
        title = str(payload.get("title") or "").strip()
        if not title:
            return jsonify({"ok": False, "error": "VALIDATION_ERROR", "message": "title cannot be empty", "field": "title"}), 400
        item.title = title

    if "description" in payload:
        next_description = (payload.get("description") or "").strip()
        if _listing_description_blocked(next_description):
            return jsonify(
                {
                    "ok": False,
                    "error": "DESCRIPTION_CONTACT_BLOCKED",
                    "message": DESCRIPTION_BLOCK_MESSAGE,
                }
            ), 400
        item.description = next_description
    if "state" in payload:
        item.state = (payload.get("state") or "").strip()
    if "city" in payload:
        item.city = (payload.get("city") or "").strip()
    if "locality" in payload:
        item.locality = (payload.get("locality") or "").strip()
    if "category" in payload:
        item.category = (payload.get("category") or "").strip() or item.category
    if "category_id" in payload and hasattr(item, "category_id"):
        item.category_id = _maybe_int(payload.get("category_id"))
    if "brand_id" in payload and hasattr(item, "brand_id"):
        item.brand_id = _maybe_int(payload.get("brand_id"))
    if "model_id" in payload and hasattr(item, "model_id"):
        item.model_id = _maybe_int(payload.get("model_id"))
    if (
        "listing_type" in payload
        or "vehicle_metadata" in payload
        or "energy_metadata" in payload
        or "real_estate_metadata" in payload
        or "metadata" in payload
        or "category_id" in payload
        or "category" in payload
        or "delivery_available" in payload
        or "inspection_required" in payload
    ):
        vehicle_payload = _parse_json_map(payload.get("vehicle_metadata"))
        energy_payload = _parse_json_map(payload.get("energy_metadata"))
        real_estate_payload = _parse_json_map(payload.get("real_estate_metadata"))
        shared_payload = _parse_json_map(payload.get("metadata"))
        if not vehicle_payload:
            vehicle_payload = dict(shared_payload)
        if not energy_payload:
            energy_payload = dict(shared_payload)
        if not real_estate_payload:
            real_estate_payload = dict(shared_payload)
        ok_meta, meta_error = _apply_vertical_metadata_to_listing(
            item,
            category_id=_maybe_int(getattr(item, "category_id", None)),
            category_name=str(getattr(item, "category", "") or ""),
            listing_type_raw=str(payload.get("listing_type") or ""),
            vehicle_payload=vehicle_payload,
            energy_payload=energy_payload,
            real_estate_payload=real_estate_payload,
            delivery_available_raw=payload.get("delivery_available"),
            inspection_required_raw=payload.get("inspection_required"),
            is_admin=_is_admin(u),
            approval_status_raw=str(payload.get("approval_status") or ""),
        )
        if not ok_meta:
            return jsonify(meta_error or {"ok": False, "error": "VALIDATION_FAILED"}), 400
    customer_profile_keys_present = any((key in payload) for key in _CUSTOMER_PAYOUT_FIELDS)
    if "customer_payout_profile" in payload or customer_profile_keys_present:
        is_merchant_owner = _account_role(_maybe_int(getattr(item, "user_id", None))) == "merchant"
        ok_profile, customer_profile, profile_error = _normalize_customer_payout_profile(
            payload.get("customer_payout_profile"),
            fallback=payload,
            required=bool(is_merchant_owner and not _is_admin(u)),
        )
        if not ok_profile:
            return jsonify(profile_error or {"ok": False, "error": "CUSTOMER_PAYOUT_PROFILE_INVALID"}), 400
        if customer_profile is not None:
            item.customer_payout_profile_json = json.dumps(customer_profile, separators=(",", ":"))
            item.customer_profile_updated_at = datetime.utcnow()
            item.customer_profile_updated_by = int(u.id)
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
            try:
                ensure_image_unique(
                    image_url=incoming,
                    source="listing_update",
                    uploader_user_id=int(u.id),
                    listing_id=int(item.id),
                    allow_same_entity=True,
                    upload_dir=UPLOAD_DIR,
                )
            except DuplicateImageError as dup:
                payload = dup.to_payload()
                payload["trace_id"] = get_request_id()
                return jsonify(payload), 409
            except Exception:
                return jsonify(
                    {
                        "ok": False,
                        "code": "IMAGE_FINGERPRINT_FAILED",
                        "message": "Could not validate image uniqueness.",
                        "trace_id": get_request_id(),
                    }
                ), 400
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
        _invalidate_listing_read_caches(int(item.id))
        _enqueue_search_index(int(item.id))
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

    try:
        try:
            queue_item_unavailable_notifications(entity="listing", entity_id=int(item.id), title=item.title or "Listing")
        except Exception:
            db.session.rollback()
        db.session.delete(item)
        db.session.commit()
        _invalidate_listing_read_caches(int(listing_id))
        _enqueue_search_delete(int(listing_id))
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
    category = "declutter"
    category_id = None
    brand_id = None
    model_id = None
    listing_type_raw = ""
    vehicle_payload: dict = {}
    energy_payload: dict = {}
    real_estate_payload: dict = {}
    shared_metadata_payload: dict = {}
    customer_payout_payload: dict = {}
    customer_payout_fallback: dict = {}
    delivery_available_raw = None
    inspection_required_raw = None
    approval_status_raw = ""
    uploaded_image_bytes = None
    image_source = "unknown"

    # 1) Multipart upload
    if request.content_type and "multipart/form-data" in (request.content_type or ""):
        title = (request.form.get("title") or "").strip()
        description = (request.form.get("description") or "").strip()

        state = (request.form.get("state") or "").strip()
        city = (request.form.get("city") or "").strip()
        locality = (request.form.get("locality") or "").strip()
        category = (request.form.get("category") or category).strip() or category
        category_id = _maybe_int(request.form.get("category_id"))
        brand_id = _maybe_int(request.form.get("brand_id"))
        model_id = _maybe_int(request.form.get("model_id"))
        listing_type_raw = (request.form.get("listing_type") or "").strip().lower()
        vehicle_payload = _parse_json_map(request.form.get("vehicle_metadata"))
        energy_payload = _parse_json_map(request.form.get("energy_metadata"))
        real_estate_payload = _parse_json_map(request.form.get("real_estate_metadata"))
        shared_metadata_payload = _parse_json_map(request.form.get("metadata"))
        customer_payout_payload = _parse_json_map(request.form.get("customer_payout_profile"))
        customer_payout_fallback = {
            key: request.form.get(key)
            for key in _CUSTOMER_PAYOUT_FIELDS
            if request.form.get(key) not in (None, "")
        }
        delivery_available_raw = request.form.get("delivery_available")
        inspection_required_raw = request.form.get("inspection_required")
        approval_status_raw = (request.form.get("approval_status") or "").strip().lower()

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

            uploaded_image_bytes = file.read()
            file.stream.seek(0)
            save_path = os.path.join(UPLOAD_DIR, safe_name)
            file.save(save_path)

            # Store RELATIVE path in DB (portable across emulator/localhost/prod)
            stored_image_path = f"/api/uploads/{safe_name}"
            image_source = "upload"

    # 2) JSON fallback
    else:
        payload = request.get_json(silent=True) or {}
        title = (payload.get("title") or "").strip()
        description = (payload.get("description") or "").strip()

        state = (payload.get("state") or "").strip()
        city = (payload.get("city") or "").strip()
        locality = (payload.get("locality") or "").strip()
        category = (payload.get("category") or category).strip() or category
        category_id = _maybe_int(payload.get("category_id"))
        brand_id = _maybe_int(payload.get("brand_id"))
        model_id = _maybe_int(payload.get("model_id"))
        listing_type_raw = (payload.get("listing_type") or "").strip().lower()
        vehicle_payload = _parse_json_map(payload.get("vehicle_metadata"))
        energy_payload = _parse_json_map(payload.get("energy_metadata"))
        real_estate_payload = _parse_json_map(payload.get("real_estate_metadata"))
        shared_metadata_payload = _parse_json_map(payload.get("metadata"))
        customer_payout_payload = _parse_json_map(payload.get("customer_payout_profile"))
        customer_payout_fallback = {
            key: payload.get(key)
            for key in _CUSTOMER_PAYOUT_FIELDS
            if payload.get(key) not in (None, "")
        }
        delivery_available_raw = payload.get("delivery_available")
        inspection_required_raw = payload.get("inspection_required")
        approval_status_raw = (payload.get("approval_status") or "").strip().lower()

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
            image_source = "url"

    if not title:
        return jsonify({"message": "title is required"}), 400
    if _listing_description_blocked(description):
        return jsonify(
            {
                "ok": False,
                "error": "DESCRIPTION_CONTACT_BLOCKED",
                "message": DESCRIPTION_BLOCK_MESSAGE,
            }
        ), 400

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
    seller_role = _seller_role(user_id)
    requires_customer_profile = _account_role(user_id) == "merchant"
    ok_profile, customer_profile, profile_error = _normalize_customer_payout_profile(
        customer_payout_payload,
        fallback=customer_payout_fallback,
        required=requires_customer_profile,
    )
    if not ok_profile:
        return jsonify(profile_error or {"ok": False, "error": "CUSTOMER_PAYOUT_PROFILE_INVALID"}), 400

    listing = Listing(
        user_id=user_id,
        title=title,
        state=state,
        city=city,
        locality=locality,
        description=description,
        category=category,
        category_id=category_id,
        brand_id=brand_id,
        model_id=model_id,
        listing_type=listing_type_raw or "declutter",
        price=price,
        image_path=stored_image_path,
    )
    if customer_profile is not None:
        listing.customer_payout_profile_json = json.dumps(customer_profile, separators=(",", ":"))
        listing.customer_profile_updated_at = datetime.utcnow()
        listing.customer_profile_updated_by = int(user_id)

    if not vehicle_payload and shared_metadata_payload:
        vehicle_payload = dict(shared_metadata_payload)
    if not energy_payload and shared_metadata_payload:
        energy_payload = dict(shared_metadata_payload)
    if not real_estate_payload and shared_metadata_payload:
        real_estate_payload = dict(shared_metadata_payload)
    ok_meta, meta_error = _apply_vertical_metadata_to_listing(
        listing,
        category_id=category_id,
        category_name=category,
        listing_type_raw=listing_type_raw,
        vehicle_payload=vehicle_payload,
        energy_payload=energy_payload,
        real_estate_payload=real_estate_payload,
        delivery_available_raw=delivery_available_raw,
        inspection_required_raw=inspection_required_raw,
        is_admin=_is_admin(owner_user),
        approval_status_raw=approval_status_raw,
    )
    if not ok_meta:
        return jsonify(meta_error or {"ok": False, "error": "VALIDATION_FAILED"}), 400

    account_role = _account_role(user_id)
    ok, info = enforce_listing_cap(
        int(user_id),
        account_role,
        str(getattr(listing, "listing_type", "declutter") or "declutter"),
    )
    if not ok:
        return jsonify(info), 403

    _apply_pricing_for_listing(listing, base_price=price, seller_role=seller_role)

    try:
        try:
            record_event(
                "listing_create",
                user=owner_user,
                context={"title": title[:120], "state": state or "", "price": float(price or 0.0)},
                request_id=request.headers.get("X-Request-ID"),
            )
        except Exception:
            db.session.rollback()
        db.session.add(listing)
        db.session.flush()
        if stored_image_path:
            fp = ensure_image_unique(
                image_url=stored_image_path,
                image_bytes=uploaded_image_bytes,
                source=image_source,
                uploader_user_id=int(user_id),
                listing_id=int(listing.id),
                allow_same_entity=True,
                upload_dir=UPLOAD_DIR,
            )
            if fp.listing_id != int(listing.id):
                fp.listing_id = int(listing.id)
                db.session.add(fp)
        db.session.commit()
        _invalidate_listing_read_caches(int(listing.id))
        _enqueue_search_index(int(listing.id))

        base = _base_url()
        return jsonify({"ok": True, "listing": listing.to_dict(base_url=base)}), 201

    except DuplicateImageError as dup:
        db.session.rollback()
        payload = dup.to_payload()
        payload["trace_id"] = get_request_id()
        return jsonify(payload), 409
    except ValueError:
        db.session.rollback()
        return jsonify(
            {
                "ok": False,
                "code": "IMAGE_FINGERPRINT_FAILED",
                "message": "Could not validate image uniqueness.",
                "trace_id": get_request_id(),
            }
        ), 400
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
