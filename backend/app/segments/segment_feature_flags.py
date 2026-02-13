from __future__ import annotations

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User
from app.utils.autopilot import get_settings
from app.utils.feature_flags import get_all_flags, public_flag_subset, update_flags
from app.utils.jwt_utils import decode_token, get_bearer_token


flags_bp = Blueprint("flags_bp", __name__, url_prefix="/api")


def _current_user() -> User | None:
    token = get_bearer_token(request.headers.get("Authorization", ""))
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
        return None


def _is_admin(user: User | None) -> bool:
    if not user:
        return False
    role = (getattr(user, "role", None) or "").strip().lower()
    if role == "admin":
        return True
    try:
        return int(getattr(user, "id", 0) or 0) == 1
    except Exception:
        return False


@flags_bp.get("/admin/flags")
def admin_get_flags():
    user = _current_user()
    if not _is_admin(user):
        return jsonify({"message": "Forbidden"}), 403
    settings = get_settings()
    return jsonify({"ok": True, "flags": get_all_flags(settings)}), 200


@flags_bp.put("/admin/flags")
def admin_put_flags():
    user = _current_user()
    if not _is_admin(user):
        return jsonify({"message": "Forbidden"}), 403
    payload = request.get_json(silent=True) or {}
    updates = payload.get("flags") if isinstance(payload.get("flags"), dict) else payload
    if not isinstance(updates, dict):
        return jsonify({"ok": False, "message": "flags payload must be an object"}), 400
    settings = get_settings()
    flags = update_flags(updates, updated_by=int(user.id), settings=settings)
    return jsonify({"ok": True, "flags": flags}), 200


@flags_bp.get("/public/config")
def public_config():
    settings = get_settings()
    return jsonify({"ok": True, "config": public_flag_subset(settings)}), 200
