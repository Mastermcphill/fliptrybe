from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, UserSettings
from app.utils.jwt_utils import decode_token

settings_bp = Blueprint("settings_bp", __name__, url_prefix="/api/settings")
preferences_bp = Blueprint("preferences_bp", __name__, url_prefix="/api/me")

_INIT_DONE = False


@settings_bp.before_app_request
def _ensure_tables_once():
    global _INIT_DONE
    if _INIT_DONE:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _INIT_DONE = True


def _bearer_token() -> str | None:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    return header.replace("Bearer ", "", 1).strip() or None


def _current_user() -> User | None:
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


@settings_bp.get("")
def get_settings():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    s = UserSettings.query.filter_by(user_id=u.id).first()
    if not s:
        s = UserSettings(user_id=u.id)
        try:
            db.session.add(s)
            db.session.commit()
        except Exception:
            db.session.rollback()
    return jsonify({"ok": True, "settings": s.to_dict()}), 200


@settings_bp.post("")
def update_settings():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    payload = request.get_json(silent=True) or {}

    s = UserSettings.query.filter_by(user_id=u.id).first()
    if not s:
        s = UserSettings(user_id=u.id)

    def _b(v, default=False):
        if v is None:
            return default
        if isinstance(v, bool):
            return v
        return str(v).lower() in ("1", "true", "yes", "y", "on")

    s.notif_in_app = _b(payload.get("notif_in_app"), True)
    s.notif_sms = _b(payload.get("notif_sms"), False)
    s.notif_whatsapp = _b(payload.get("notif_whatsapp"), False)
    s.dark_mode = _b(payload.get("dark_mode"), False)
    s.updated_at = datetime.utcnow()

    try:
        db.session.add(s)
        db.session.commit()
        return jsonify({"ok": True, "settings": s.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


def _ensure_user_settings(user_id: int) -> UserSettings:
    row = UserSettings.query.filter_by(user_id=int(user_id)).first()
    if row:
        return row
    row = UserSettings(user_id=int(user_id))
    db.session.add(row)
    db.session.commit()
    return row


@preferences_bp.get("/preferences")
def get_preferences():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    try:
        s = _ensure_user_settings(int(u.id))
        return jsonify(
            {
                "ok": True,
                "preferences": {
                    "preferred_city": (getattr(s, "preferred_city", "") or ""),
                    "preferred_state": (getattr(s, "preferred_state", "") or ""),
                },
            }
        ), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "PREFERENCES_READ_FAILED", "message": str(exc)}), 500


@preferences_bp.post("/preferences")
def set_preferences():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    preferred_city = str(payload.get("preferred_city") or "").strip()
    preferred_state = str(payload.get("preferred_state") or "").strip()
    try:
        s = _ensure_user_settings(int(u.id))
        s.preferred_city = preferred_city[:80] if preferred_city else None
        s.preferred_state = preferred_state[:80] if preferred_state else None
        s.updated_at = datetime.utcnow()
        db.session.add(s)
        db.session.commit()
        return jsonify(
            {
                "ok": True,
                "preferences": {
                    "preferred_city": (s.preferred_city or ""),
                    "preferred_state": (s.preferred_state or ""),
                },
            }
        ), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "PREFERENCES_UPDATE_FAILED", "message": str(exc)}), 500
