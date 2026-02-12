from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from app.extensions import db
from app.models import (
    Listing,
    Shortlet,
    ListingFavorite,
    ShortletFavorite,
    ListingView,
    ShortletView,
    NotificationQueue,
    MerchantFollow,
    User,
)
from app.utils.autopilot import get_settings


HEAT_NORMAL = "normal"
HEAT_HOT = "hot"
HEAT_HOTTER = "hotter"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _day_key(dt: datetime | None = None) -> str:
    base = dt or _utcnow()
    return base.date().isoformat()


def _normalize_text(value: str | None) -> str:
    return (value or "").strip().lower()


def _session_key(user_id: int | None, supplied: str | None) -> str:
    raw = (supplied or "").strip()
    if raw:
        return raw[:120]
    if user_id:
        return f"user:{int(user_id)}"
    return "guest:anonymous"


def compute_heat_level(*, favorites_last_24h: int, favorites_last_7d: int) -> tuple[str, int]:
    if favorites_last_24h >= 10 or favorites_last_7d >= 30:
        return HEAT_HOTTER, 2
    if favorites_last_24h >= 5 or favorites_last_7d >= 15:
        return HEAT_HOT, 1
    return HEAT_NORMAL, 0


def _queue_watcher_notifications(*, entity: str, entity_id: int, heat_level: str) -> None:
    settings = get_settings()
    if not bool(getattr(settings, "watcher_notifications_v1", False)):
        return
    if heat_level not in (HEAT_HOT, HEAT_HOTTER):
        return

    day_token = _day_key()
    ref = f"watchers:{entity}:{int(entity_id)}:{heat_level}:{day_token}"
    existing = NotificationQueue.query.filter_by(reference=ref).first()
    if existing:
        return

    if entity == "listing":
        watcher_rows = (
            ListingFavorite.query.filter_by(listing_id=int(entity_id))
            .order_by(ListingFavorite.created_at.desc())
            .limit(500)
            .all()
        )
        user_ids = {int(r.user_id) for r in watcher_rows if r.user_id is not None}
        title = (db.session.get(Listing, int(entity_id)).title if db.session.get(Listing, int(entity_id)) else "Listing")
        message = f"{title} is now {heat_level.upper()}."
    else:
        watcher_rows = (
            ShortletFavorite.query.filter_by(shortlet_id=int(entity_id))
            .order_by(ShortletFavorite.created_at.desc())
            .limit(500)
            .all()
        )
        user_ids = {int(r.user_id) for r in watcher_rows if r.user_id is not None}
        title = (db.session.get(Shortlet, int(entity_id)).title if db.session.get(Shortlet, int(entity_id)) else "Shortlet")
        message = f"{title} is now {heat_level.upper()}."

    for uid in user_ids:
        q = NotificationQueue(
            channel="in_app",
            to=str(uid),
            message=message[:500],
            status="queued",
            reference=ref,
        )
        db.session.add(q)
    db.session.commit()


def queue_item_unavailable_notifications(*, entity: str, entity_id: int, title: str = "") -> None:
    settings = get_settings()
    if not bool(getattr(settings, "watcher_notifications_v1", False)):
        return
    day_token = _day_key()
    ref = f"watchers:{entity}:{int(entity_id)}:unavailable:{day_token}"
    if NotificationQueue.query.filter_by(reference=ref).first():
        return
    if entity == "listing":
        watcher_rows = ListingFavorite.query.filter_by(listing_id=int(entity_id)).limit(500).all()
    else:
        watcher_rows = ShortletFavorite.query.filter_by(shortlet_id=int(entity_id)).limit(500).all()
    user_ids = {int(row.user_id) for row in watcher_rows if row.user_id is not None}
    message = f"{title or 'Item'} is no longer available."
    for uid in user_ids:
        db.session.add(
            NotificationQueue(
                channel="in_app",
                to=str(uid),
                message=message[:500],
                status="queued",
                reference=ref,
            )
        )
    db.session.commit()


def _favorites_windows_for_listing(listing_id: int) -> tuple[int, int]:
    now = _utcnow()
    day_ago = now.timestamp() - 86400
    week_ago = now.timestamp() - 604800
    rows = ListingFavorite.query.filter_by(listing_id=int(listing_id)).all()
    last_24h = 0
    last_7d = 0
    for row in rows:
        created_at = row.created_at or now
        ts = created_at.timestamp()
        if ts >= day_ago:
            last_24h += 1
        if ts >= week_ago:
            last_7d += 1
    return last_24h, last_7d


def _favorites_windows_for_shortlet(shortlet_id: int) -> tuple[int, int]:
    now = _utcnow()
    day_ago = now.timestamp() - 86400
    week_ago = now.timestamp() - 604800
    rows = ShortletFavorite.query.filter_by(shortlet_id=int(shortlet_id)).all()
    last_24h = 0
    last_7d = 0
    for row in rows:
        created_at = row.created_at or now
        ts = created_at.timestamp()
        if ts >= day_ago:
            last_24h += 1
        if ts >= week_ago:
            last_7d += 1
    return last_24h, last_7d


def refresh_listing_aggregates(listing_id: int) -> dict[str, Any]:
    listing = db.session.get(Listing, int(listing_id))
    if not listing:
        return {"ok": False, "error": "LISTING_NOT_FOUND"}

    favorites_count = ListingFavorite.query.filter_by(listing_id=int(listing_id)).count()
    views_count = ListingView.query.filter_by(listing_id=int(listing_id)).count()
    last_24h, last_7d = _favorites_windows_for_listing(int(listing_id))
    heat_level, heat_score = compute_heat_level(
        favorites_last_24h=int(last_24h),
        favorites_last_7d=int(last_7d),
    )
    old_level = _normalize_text(getattr(listing, "heat_level", HEAT_NORMAL))
    listing.favorites_count = int(favorites_count)
    listing.views_count = int(views_count)
    listing.heat_level = heat_level
    listing.heat_score = int(heat_score)
    db.session.add(listing)
    db.session.commit()

    if old_level != heat_level and heat_level in (HEAT_HOT, HEAT_HOTTER):
        try:
            _queue_watcher_notifications(entity="listing", entity_id=int(listing_id), heat_level=heat_level)
        except Exception:
            db.session.rollback()

    return {
        "ok": True,
        "listing_id": int(listing_id),
        "favorites_count": int(favorites_count),
        "views_count": int(views_count),
        "heat_level": heat_level,
        "heat_score": int(heat_score),
    }


def refresh_shortlet_aggregates(shortlet_id: int) -> dict[str, Any]:
    shortlet = db.session.get(Shortlet, int(shortlet_id))
    if not shortlet:
        return {"ok": False, "error": "SHORTLET_NOT_FOUND"}

    favorites_count = ShortletFavorite.query.filter_by(shortlet_id=int(shortlet_id)).count()
    views_count = ShortletView.query.filter_by(shortlet_id=int(shortlet_id)).count()
    last_24h, last_7d = _favorites_windows_for_shortlet(int(shortlet_id))
    heat_level, heat_score = compute_heat_level(
        favorites_last_24h=int(last_24h),
        favorites_last_7d=int(last_7d),
    )
    old_level = _normalize_text(getattr(shortlet, "heat_level", HEAT_NORMAL))
    shortlet.favorites_count = int(favorites_count)
    shortlet.views_count = int(views_count)
    shortlet.heat_level = heat_level
    shortlet.heat_score = int(heat_score)
    db.session.add(shortlet)
    db.session.commit()

    if old_level != heat_level and heat_level in (HEAT_HOT, HEAT_HOTTER):
        try:
            _queue_watcher_notifications(entity="shortlet", entity_id=int(shortlet_id), heat_level=heat_level)
        except Exception:
            db.session.rollback()

    return {
        "ok": True,
        "shortlet_id": int(shortlet_id),
        "favorites_count": int(favorites_count),
        "views_count": int(views_count),
        "heat_level": heat_level,
        "heat_score": int(heat_score),
    }


def set_listing_favorite(*, listing_id: int, user_id: int, is_favorite: bool) -> dict[str, Any]:
    listing = db.session.get(Listing, int(listing_id))
    if not listing:
        return {"ok": False, "error": "LISTING_NOT_FOUND"}

    existing = ListingFavorite.query.filter_by(user_id=int(user_id), listing_id=int(listing_id)).first()
    if is_favorite and existing is None:
        db.session.add(ListingFavorite(user_id=int(user_id), listing_id=int(listing_id)))
        db.session.commit()
    elif not is_favorite and existing is not None:
        db.session.delete(existing)
        db.session.commit()

    agg = refresh_listing_aggregates(int(listing_id))
    agg["is_favorite"] = bool(
        ListingFavorite.query.filter_by(user_id=int(user_id), listing_id=int(listing_id)).first() is not None
    )
    return agg


def set_shortlet_favorite(*, shortlet_id: int, user_id: int, is_favorite: bool) -> dict[str, Any]:
    shortlet = db.session.get(Shortlet, int(shortlet_id))
    if not shortlet:
        return {"ok": False, "error": "SHORTLET_NOT_FOUND"}

    existing = ShortletFavorite.query.filter_by(user_id=int(user_id), shortlet_id=int(shortlet_id)).first()
    if is_favorite and existing is None:
        db.session.add(ShortletFavorite(user_id=int(user_id), shortlet_id=int(shortlet_id)))
        db.session.commit()
    elif not is_favorite and existing is not None:
        db.session.delete(existing)
        db.session.commit()

    agg = refresh_shortlet_aggregates(int(shortlet_id))
    agg["is_favorite"] = bool(
        ShortletFavorite.query.filter_by(user_id=int(user_id), shortlet_id=int(shortlet_id)).first() is not None
    )
    return agg


def record_listing_view(*, listing_id: int, user_id: int | None, session_key: str | None) -> dict[str, Any]:
    listing = db.session.get(Listing, int(listing_id))
    if not listing:
        return {"ok": False, "error": "LISTING_NOT_FOUND"}

    key = _session_key(user_id, session_key)
    row = ListingView.query.filter_by(
        listing_id=int(listing_id),
        viewer_user_id=int(user_id) if user_id is not None else None,
        session_key=key,
        view_date=_day_key(),
    ).first()
    if row is None:
        db.session.add(
            ListingView(
                listing_id=int(listing_id),
                viewer_user_id=int(user_id) if user_id is not None else None,
                session_key=key,
                view_date=_day_key(),
            )
        )
        db.session.commit()
    agg = refresh_listing_aggregates(int(listing_id))
    agg["deduped"] = row is not None
    return agg


def record_shortlet_view(*, shortlet_id: int, user_id: int | None, session_key: str | None) -> dict[str, Any]:
    shortlet = db.session.get(Shortlet, int(shortlet_id))
    if not shortlet:
        return {"ok": False, "error": "SHORTLET_NOT_FOUND"}
    key = _session_key(user_id, session_key)
    row = ShortletView.query.filter_by(
        shortlet_id=int(shortlet_id),
        viewer_user_id=int(user_id) if user_id is not None else None,
        session_key=key,
        view_date=_day_key(),
    ).first()
    if row is None:
        db.session.add(
            ShortletView(
                shortlet_id=int(shortlet_id),
                viewer_user_id=int(user_id) if user_id is not None else None,
                session_key=key,
                view_date=_day_key(),
            )
        )
        db.session.commit()
    agg = refresh_shortlet_aggregates(int(shortlet_id))
    agg["deduped"] = row is not None
    return agg


def ranking_for_listing(
    listing: Listing,
    *,
    preferred_city: str = "",
    preferred_state: str = "",
) -> tuple[int, list[str]]:
    score = 0
    reasons: list[str] = []
    city = _normalize_text(getattr(listing, "city", ""))
    state = _normalize_text(getattr(listing, "state", ""))
    pref_city = _normalize_text(preferred_city)
    pref_state = _normalize_text(preferred_state)

    if pref_city and city and pref_city == city:
        score += 100
        reasons.append("CITY_MATCH")
    if pref_state and state and pref_state == state:
        score += 40
        reasons.append("STATE_MATCH")

    heat_level = _normalize_text(getattr(listing, "heat_level", HEAT_NORMAL))
    if heat_level == HEAT_HOTTER:
        score += 40
        reasons.append("HOTTER")
    elif heat_level == HEAT_HOT:
        score += 20
        reasons.append("HOT")

    created_at = getattr(listing, "created_at", None)
    if created_at:
        days = max(0.0, (_utcnow() - created_at).total_seconds() / 86400.0)
        if days <= 7.0:
            recency = int(round((7.0 - days) / 7.0 * 30.0))
            if recency > 0:
                score += recency
                reasons.append("NEW")

    quality = 0
    image_path = (getattr(listing, "image_path", None) or "").strip()
    if image_path:
        quality += 8
    description = (getattr(listing, "description", None) or "").strip()
    if len(description) >= 80:
        quality += 8
    elif len(description) >= 30:
        quality += 4
    condition = (getattr(listing, "condition", None) or "").strip() if hasattr(listing, "condition") else ""
    if condition:
        quality += 4
    if quality > 20:
        quality = 20
    if quality > 0:
        score += quality
        reasons.append("QUALITY")
    if not reasons:
        reasons.append("BASELINE")
    return int(score), reasons


def ranking_for_shortlet(
    shortlet: Shortlet,
    *,
    preferred_city: str = "",
    preferred_state: str = "",
) -> tuple[int, list[str]]:
    score = 0
    reasons: list[str] = []
    city = _normalize_text(getattr(shortlet, "city", ""))
    state = _normalize_text(getattr(shortlet, "state", ""))
    pref_city = _normalize_text(preferred_city)
    pref_state = _normalize_text(preferred_state)

    if pref_city and city and pref_city == city:
        score += 100
        reasons.append("CITY_MATCH")
    if pref_state and state and pref_state == state:
        score += 40
        reasons.append("STATE_MATCH")

    heat_level = _normalize_text(getattr(shortlet, "heat_level", HEAT_NORMAL))
    if heat_level == HEAT_HOTTER:
        score += 40
        reasons.append("HOTTER")
    elif heat_level == HEAT_HOT:
        score += 20
        reasons.append("HOT")

    created_at = getattr(shortlet, "created_at", None)
    if created_at:
        days = max(0.0, (_utcnow() - created_at).total_seconds() / 86400.0)
        if days <= 7.0:
            recency = int(round((7.0 - days) / 7.0 * 30.0))
            if recency > 0:
                score += recency
                reasons.append("NEW")

    quality = 0
    image_path = (getattr(shortlet, "image_path", None) or "").strip()
    if image_path:
        quality += 8
    description = (getattr(shortlet, "description", None) or "").strip()
    if len(description) >= 80:
        quality += 8
    elif len(description) >= 30:
        quality += 4
    if (getattr(shortlet, "property_type", None) or "").strip():
        quality += 4
    if quality > 20:
        quality = 20
    if quality > 0:
        score += quality
        reasons.append("QUALITY")
    if not reasons:
        reasons.append("BASELINE")
    return int(score), reasons


def merchant_listing_metrics(merchant_id: int) -> list[dict[str, Any]]:
    rows = Listing.query.filter_by(user_id=int(merchant_id)).order_by(Listing.created_at.desc()).all()
    items: list[dict[str, Any]] = []
    for row in rows:
        items.append(
            {
                "listing_id": int(row.id),
                "title": row.title or "",
                "views_count": int(getattr(row, "views_count", 0) or 0),
                "favorites_count": int(getattr(row, "favorites_count", 0) or 0),
                "heat_level": (getattr(row, "heat_level", HEAT_NORMAL) or HEAT_NORMAL),
            }
        )
    return items


def host_shortlet_metrics(host_id: int) -> list[dict[str, Any]]:
    rows = Shortlet.query.filter_by(owner_id=int(host_id)).order_by(Shortlet.created_at.desc()).all()
    items: list[dict[str, Any]] = []
    for row in rows:
        items.append(
            {
                "shortlet_id": int(row.id),
                "title": row.title or "",
                "views_count": int(getattr(row, "views_count", 0) or 0),
                "favorites_count": int(getattr(row, "favorites_count", 0) or 0),
                "heat_level": (getattr(row, "heat_level", HEAT_NORMAL) or HEAT_NORMAL),
            }
        )
    return items


def user_following_merchant_ids(user_id: int) -> set[int]:
    rows = MerchantFollow.query.filter_by(follower_id=int(user_id)).all()
    out: set[int] = set()
    for row in rows:
        try:
            out.add(int(row.merchant_id))
        except Exception:
            continue
    return out


def user_identity(user_id: int | None) -> dict[str, Any]:
    if not user_id:
        return {"id": None, "name": "", "email": "", "phone": ""}
    u = db.session.get(User, int(user_id))
    if not u:
        return {"id": int(user_id), "name": "", "email": "", "phone": ""}
    return {
        "id": int(u.id),
        "name": (getattr(u, "name", None) or ""),
        "email": (getattr(u, "email", None) or ""),
        "phone": (getattr(u, "phone", None) or ""),
    }
