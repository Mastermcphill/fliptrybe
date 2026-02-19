from __future__ import annotations

import os
from datetime import datetime
from typing import Any


def _env_bool(name: str, default: bool) -> bool:
    raw = (os.getenv(name) or "").strip().lower()
    if not raw:
        return bool(default)
    return raw in ("1", "true", "yes", "on")


def search_engine_name() -> str:
    return (os.getenv("SEARCH_ENGINE") or "").strip().lower()


def search_engine_is_meili() -> bool:
    return search_engine_name() == "meili"


def search_fallback_sql_enabled() -> bool:
    return _env_bool("SEARCH_FALLBACK_SQL", True)


def listings_index_name() -> str:
    return (os.getenv("SEARCH_INDEX_LISTINGS") or "listings_v1").strip()


def _to_lower(raw_value) -> str:
    return str(raw_value or "").strip().lower()


def _to_index_number(raw_value) -> int | float:
    try:
        value = float(raw_value)
    except Exception:
        return 0
    rounded_int = int(round(value))
    if abs(value - float(rounded_int)) < 1e-9:
        return int(rounded_int)
    return float(round(value, 2))


def _to_minor(raw_value) -> int:
    try:
        return int(round(float(raw_value or 0.0) * 100.0))
    except Exception:
        return 0


def _as_iso(dt_value) -> str:
    if isinstance(dt_value, datetime):
        return dt_value.isoformat()
    if dt_value is None:
        return ""
    return str(dt_value)


def _base_url_from_request_fallback() -> str:
    try:
        from flask import request

        return request.host_url.rstrip("/")
    except Exception:
        return ""


def _resolve_image_value(image_path: str, base_url: str) -> str:
    value = str(image_path or "").strip()
    if not value:
        return ""
    low = value.lower()
    if low.startswith("http://") or low.startswith("https://"):
        return value
    if not base_url:
        return value
    prefix = value if value.startswith("/") else f"/{value}"
    return f"{base_url.rstrip('/')}{prefix}"


def _bool_or_none(raw_value) -> bool | None:
    if raw_value is None:
        return None
    return bool(raw_value)


def listing_to_search_document(listing, *, base_url: str | None = None) -> dict[str, Any]:
    resolved_base_url = str(base_url or "").strip() or _base_url_from_request_fallback()
    image_path = str(getattr(listing, "image_path", "") or "")
    image = _resolve_image_value(image_path, resolved_base_url)

    price = _to_index_number(getattr(listing, "price", 0.0))
    final_price = _to_index_number(getattr(listing, "final_price", getattr(listing, "price", 0.0)))
    listing_type = str(getattr(listing, "listing_type", "") or "declutter").strip().lower() or "declutter"
    approval_status = str(getattr(listing, "approval_status", "") or "approved").strip().lower() or "approved"
    is_active = bool(getattr(listing, "is_active", True))
    category = str(getattr(listing, "category", "") or "")
    state = str(getattr(listing, "state", "") or "")
    city = str(getattr(listing, "city", "") or "")
    locality = str(getattr(listing, "locality", "") or "")
    condition = str(getattr(listing, "condition", "") or "")
    status = str(getattr(listing, "status", "") or "")
    make = str(getattr(listing, "vehicle_make", "") or "")
    model = str(getattr(listing, "vehicle_model", "") or "")
    battery_type = str(getattr(listing, "battery_type", "") or "")
    inverter_capacity = str(getattr(listing, "inverter_capacity", "") or "")
    property_type = str(getattr(listing, "property_type", "") or "")
    title_document_type = str(getattr(listing, "title_document_type", "") or "")

    return {
        "id": int(getattr(listing, "id", 0) or 0),
        "title": str(getattr(listing, "title", "") or ""),
        "description": str(getattr(listing, "description", "") or ""),
        "category": category,
        "category_ci": _to_lower(category),
        "category_id": int(getattr(listing, "category_id", 0)) if getattr(listing, "category_id", None) is not None else None,
        "brand_id": int(getattr(listing, "brand_id", 0)) if getattr(listing, "brand_id", None) is not None else None,
        "model_id": int(getattr(listing, "model_id", 0)) if getattr(listing, "model_id", None) is not None else None,
        "listing_type": listing_type,
        "state": state,
        "state_ci": _to_lower(state),
        "city": city,
        "city_ci": _to_lower(city),
        "locality": locality,
        "locality_ci": _to_lower(locality),
        "condition": condition,
        "condition_ci": _to_lower(condition),
        "status": status,
        "status_ci": _to_lower(status),
        "price": price,
        "final_price": final_price,
        "price_minor": _to_minor(getattr(listing, "price", 0.0)),
        "final_price_minor": _to_minor(getattr(listing, "final_price", getattr(listing, "price", 0.0))),
        "approval_status": approval_status,
        "is_active": is_active,
        "merchant_id": int(getattr(listing, "user_id", 0) or 0),
        "user_id": int(getattr(listing, "user_id", 0) or 0),
        "created_at": _as_iso(getattr(listing, "created_at", None)),
        "heat_score": int(getattr(listing, "heat_score", 0) or 0),
        "ranking_score": int(getattr(listing, "heat_score", 0) or 0),
        "delivery_available": _bool_or_none(getattr(listing, "delivery_available", None)),
        "inspection_required": _bool_or_none(getattr(listing, "inspection_required", None)),
        "furnished": _bool_or_none(getattr(listing, "furnished", None)),
        "serviced": _bool_or_none(getattr(listing, "serviced", None)),
        "property_type": property_type,
        "property_type_ci": _to_lower(property_type),
        "make": make,
        "make_ci": _to_lower(make),
        "model": model,
        "model_ci": _to_lower(model),
        "year": int(getattr(listing, "vehicle_year", 0)) if getattr(listing, "vehicle_year", None) is not None else None,
        "vehicle_make": make,
        "vehicle_model": model,
        "vehicle_year": int(getattr(listing, "vehicle_year", 0)) if getattr(listing, "vehicle_year", None) is not None else None,
        "battery_type": battery_type,
        "battery_type_ci": _to_lower(battery_type),
        "inverter_capacity": inverter_capacity,
        "inverter_capacity_ci": _to_lower(inverter_capacity),
        "lithium_only": bool(getattr(listing, "lithium_only", False)),
        "bundle_badge": bool(getattr(listing, "bundle_badge", False)),
        "bedrooms": int(getattr(listing, "bedrooms", 0)) if getattr(listing, "bedrooms", None) is not None else None,
        "bathrooms": int(getattr(listing, "bathrooms", 0)) if getattr(listing, "bathrooms", None) is not None else None,
        "land_size": float(getattr(listing, "land_size", 0.0)) if getattr(listing, "land_size", None) is not None else None,
        "title_document_type": title_document_type,
        "title_document_type_ci": _to_lower(title_document_type),
        "image": image,
        "image_path": image_path,
        "image_filename": str(getattr(listing, "image_filename", "") or ""),
    }


def listing_should_be_indexed(listing) -> bool:
    if listing is None:
        return False
    try:
        listing_id = int(getattr(listing, "id", 0) or 0)
    except Exception:
        listing_id = 0
    if listing_id <= 0:
        return False
    if not bool(getattr(listing, "is_active", True)):
        return False
    listing_type = str(getattr(listing, "listing_type", "") or "declutter").strip().lower()
    approval_status = str(getattr(listing, "approval_status", "") or "approved").strip().lower()
    if listing_type == "vehicle":
        return approval_status == "approved"
    return approval_status in ("", "approved")
