from __future__ import annotations

from sqlalchemy import or_

from app.extensions import db
from app.models import Listing, Shortlet


def listing_limit_for_role(role: str) -> int | None:
    r = (role or "buyer").strip().lower()
    if r == "merchant":
        return None
    if r == "buyer":
        return 10
    if r in ("driver", "inspector"):
        return 20
    return 10


def _listing_active_filter(q):
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


def active_declutter_count(user_id: int) -> int:
    try:
        q = Listing.query.filter(Listing.user_id == int(user_id))
        q = _listing_active_filter(q)
        return int(q.count())
    except Exception:
        return 0


def active_shortlet_count(user_id: int) -> int:
    try:
        if not hasattr(Shortlet, "owner_id"):
            return 0
        q = Shortlet.query.filter(Shortlet.owner_id == int(user_id))
        return int(q.count())
    except Exception:
        return 0


def enforce_listing_cap(user_id: int, role: str, listing_type: str) -> tuple[bool, dict]:
    limit = listing_limit_for_role(role)
    if limit is None:
        return True, {}

    ltype = (listing_type or "declutter").strip().lower()
    active = 0
    if ltype == "shortlet":
        active = active_shortlet_count(int(user_id))
    else:
        active = active_declutter_count(int(user_id))

    if active >= limit:
        return False, {"message": f"Listing limit exceeded for role {role}", "limit": limit}
    return True, {}
