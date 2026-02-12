from __future__ import annotations

from typing import Any

from sqlalchemy import and_, or_, text

from app.extensions import db
from app.models import Listing


def _dialect() -> str:
    try:
        return (db.session.bind.dialect.name or "").lower()
    except Exception:
        return ""


def _column_exists(table_name: str, column_name: str) -> bool:
    try:
        cols = db.inspect(db.session.bind).get_columns(table_name)
        return any((c.get("name") or "") == column_name for c in cols)
    except Exception:
        return False


def _safe_float(raw, default: float | None = None) -> float | None:
    if raw is None:
        return default
    try:
        return float(raw)
    except Exception:
        return default


def _serialize_listing(row: Listing) -> dict[str, Any]:
    created_at = getattr(row, "created_at", None)
    return {
        "id": int(row.id),
        "title": (row.title or ""),
        "description": (row.description or ""),
        "price": float(getattr(row, "price", 0.0) or 0.0),
        "category": (getattr(row, "category", "") or ""),
        "state": (getattr(row, "state", "") or ""),
        "city": (getattr(row, "city", "") or ""),
        "condition": (getattr(row, "condition", "") or ""),
        "image_path": (getattr(row, "image_path", "") or ""),
        "image_filename": (getattr(row, "image_filename", "") or ""),
        "user_id": int(getattr(row, "user_id", 0) or 0),
        "created_at": created_at.isoformat() if created_at else None,
    }


def search_listings_v2(
    *,
    q: str = "",
    category: str = "",
    state: str = "",
    min_price: float | None = None,
    max_price: float | None = None,
    condition: str = "",
    status: str = "",
    delivery_available: bool | None = None,
    inspection_required: bool | None = None,
    sort: str = "relevance",
    limit: int = 20,
    offset: int = 0,
    include_inactive: bool = False,
) -> dict[str, Any]:
    query = Listing.query

    if not include_inactive:
        if hasattr(Listing, "is_active"):
            query = query.filter(getattr(Listing, "is_active").is_(True))

    if category:
        query = query.filter(Listing.category.ilike(category))
    if state:
        query = query.filter(Listing.state.ilike(state))
    if condition and hasattr(Listing, "condition"):
        like_condition = f"%{condition.strip()}%"
        query = query.filter(getattr(Listing, "condition").ilike(like_condition))

    status_key = (status or "").strip().lower()
    if status_key and status_key not in ("all", "any"):
        if status_key in ("active", "inactive") and hasattr(Listing, "is_active"):
            query = query.filter(getattr(Listing, "is_active").is_(status_key == "active"))
        elif hasattr(Listing, "status"):
            query = query.filter(getattr(Listing, "status").ilike(status_key))

    if delivery_available is not None and hasattr(Listing, "delivery_available"):
        query = query.filter(getattr(Listing, "delivery_available").is_(bool(delivery_available)))
    if inspection_required is not None and hasattr(Listing, "inspection_required"):
        query = query.filter(getattr(Listing, "inspection_required").is_(bool(inspection_required)))

    min_p = _safe_float(min_price, None)
    max_p = _safe_float(max_price, None)
    if min_p is not None:
        query = query.filter(Listing.price >= min_p)
    if max_p is not None:
        query = query.filter(Listing.price <= max_p)

    search_text = (q or "").strip()
    dialect = _dialect()
    has_search_vector = _column_exists("listings", "search_vector")
    relevance_order_applied = False

    if search_text:
        like = f"%{search_text}%"
        if dialect == "postgresql" and has_search_vector:
            # FTS + trigram fallback in one query predicate.
            query = query.filter(
                and_(
                    text(
                        "((search_vector @@ plainto_tsquery('english', :sv_q)) "
                        "OR similarity(title, :sv_q) > 0.15 "
                        "OR similarity(description, :sv_q) > 0.10)"
                    )
                )
            ).params(sv_q=search_text)
            if sort == "relevance":
                query = query.order_by(
                    text(
                        "("
                        "ts_rank_cd(search_vector, plainto_tsquery('english', :rank_q))"
                        " + similarity(title, :rank_q)"
                        " + (0.05 / (1 + EXTRACT(EPOCH FROM (now() - COALESCE(created_at, now()))) / 86400))"
                        ") DESC"
                    )
                ).params(rank_q=search_text)
                relevance_order_applied = True
        else:
            query = query.filter(
                or_(
                    Listing.title.ilike(like),
                    Listing.description.ilike(like),
                    Listing.category.ilike(like),
                    Listing.state.ilike(like),
                    Listing.city.ilike(like),
                )
            )

    raw_sort = (sort or "relevance").strip().lower()
    if raw_sort in ("price_low", "price_low_to_high", "priceasc"):
        sort_key = "price_asc"
    elif raw_sort in ("price_high", "price_high_to_low", "pricedesc"):
        sort_key = "price_desc"
    elif raw_sort in ("new", "latest"):
        sort_key = "newest"
    elif raw_sort in ("relevance", "newest", "price_asc", "price_desc"):
        sort_key = raw_sort
    else:
        sort_key = "relevance"
    if sort_key == "price_asc":
        query = query.order_by(Listing.price.asc(), Listing.id.desc())
    elif sort_key == "price_desc":
        query = query.order_by(Listing.price.desc(), Listing.id.desc())
    elif sort_key == "newest":
        if hasattr(Listing, "created_at"):
            query = query.order_by(Listing.created_at.desc(), Listing.id.desc())
        else:
            query = query.order_by(Listing.id.desc())
    elif not relevance_order_applied:
        if hasattr(Listing, "created_at"):
            query = query.order_by(Listing.created_at.desc(), Listing.id.desc())
        else:
            query = query.order_by(Listing.id.desc())

    safe_limit = max(1, min(int(limit or 20), 100))
    safe_offset = max(0, int(offset or 0))

    total = query.count()
    rows = query.offset(safe_offset).limit(safe_limit).all()
    items = [_serialize_listing(row) for row in rows]

    return {
        "ok": True,
        "items": items,
        "total": int(total),
        "limit": int(safe_limit),
        "offset": int(safe_offset),
        "sort": sort_key,
        "q": search_text,
        "supported_filters": {
            "delivery_available": hasattr(Listing, "delivery_available"),
            "inspection_required": hasattr(Listing, "inspection_required"),
        },
    }
