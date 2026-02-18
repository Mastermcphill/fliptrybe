from __future__ import annotations

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models.user import User
from app.models.listing import Listing
from app.utils.jwt_utils import decode_token, get_bearer_token

admin_bp = Blueprint("admin_bp", __name__, url_prefix="/api/admin")


def _current_user() -> User | None:
    token = get_bearer_token(request.headers.get("Authorization", ""))
    if not token:
        return None
    payload = decode_token(token)
    if not payload:
        return None
    try:
        uid = int(payload.get("sub"))
    except Exception:
        return None
    try:
        return db.session.get(User, uid)
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
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
    return jsonify(
        {
            "ok": True,
            "stats": {
                "users": User.query.count(),
                "listings": Listing.query.count(),
                "orders": 0,
                "reports": 0,
            },
        }
    ), 200


@admin_bp.post("/listings/<int:listing_id>/disable")
def disable_listing(listing_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    return jsonify({"ok": True, "listing_id": listing_id, "action": "disabled"}), 200


@admin_bp.post("/users/<int:user_id>/disable")
def disable_user(user_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    return jsonify({"ok": True, "user_id": user_id, "action": "disabled"}), 200
