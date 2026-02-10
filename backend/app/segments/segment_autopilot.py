from __future__ import annotations

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User
from app.utils.jwt_utils import decode_token
from app.utils.autopilot import get_settings, tick
from app.integrations.payments.factory import payment_health
from app.integrations.messaging.factory import messaging_health

autopilot_bp = Blueprint("autopilot_bp", __name__, url_prefix="/api/admin/autopilot")

_INIT = False


@autopilot_bp.before_app_request
def _ensure_tables_once():
    global _INIT
    if _INIT:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _INIT = True


def _bearer():
    h = request.headers.get("Authorization", "")
    if not h.startswith("Bearer "):
        return None
    return h.replace("Bearer ", "", 1).strip()


def _current_user():
    tok = _bearer()
    if not tok:
        return None
    payload = decode_token(tok)
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


def _is_admin(u):
    if not u:
        return False
    try:
        if int(getattr(u, "id", 0) or 0) == 1:
            return True
    except Exception:
        pass
    return (getattr(u, "role", "") or "").strip().lower() == "admin"


def _as_bool(value, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return int(value) == 1
    if isinstance(value, str):
        return value.strip().lower() in ("1", "true", "yes", "y", "on")
    return default


def _settings_payload(s):
    base = s.to_dict()
    p_health = payment_health(s)
    m_health = messaging_health(s)
    base["integrations"] = {
        "payments_provider": base.get("payments_provider"),
        "paystack_enabled": base.get("paystack_enabled"),
        "termii_enabled_sms": base.get("termii_enabled_sms"),
        "termii_enabled_wa": base.get("termii_enabled_wa"),
        "integrations_mode": base.get("integrations_mode"),
    }
    base["integration_health"] = {
        "payments": p_health,
        "messaging": m_health,
    }
    return base


@autopilot_bp.get("")
def get_status():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    s = get_settings()
    return jsonify({"ok": True, "settings": _settings_payload(s)}), 200


@autopilot_bp.post("/toggle")
def toggle():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    s = get_settings()
    data = request.get_json(silent=True) or {}
    enabled = data.get("enabled")
    if enabled is None:
        enabled = not bool(s.enabled)
    s.enabled = bool(enabled)
    db.session.add(s)
    db.session.commit()
    return jsonify({"ok": True, "settings": _settings_payload(s)}), 200


@autopilot_bp.post("/settings")
def update_settings():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    data = request.get_json(silent=True) or {}
    s = get_settings()

    mode = (data.get("integrations_mode") or s.integrations_mode or "disabled").strip().lower()
    provider = (data.get("payments_provider") or s.payments_provider or "mock").strip().lower()
    if mode not in ("disabled", "sandbox", "live"):
        return jsonify({"ok": False, "message": "integrations_mode must be disabled|sandbox|live"}), 400
    if provider not in ("mock", "paystack"):
        return jsonify({"ok": False, "message": "payments_provider must be mock|paystack"}), 400

    s.integrations_mode = mode
    s.payments_provider = provider
    s.paystack_enabled = _as_bool(data.get("paystack_enabled"), bool(s.paystack_enabled))
    s.termii_enabled_sms = _as_bool(data.get("termii_enabled_sms"), bool(s.termii_enabled_sms))
    s.termii_enabled_wa = _as_bool(data.get("termii_enabled_wa"), bool(s.termii_enabled_wa))
    db.session.add(s)
    db.session.commit()
    return jsonify({"ok": True, "settings": _settings_payload(s)}), 200


@autopilot_bp.post("/tick")
def manual_tick():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    res = tick()
    return jsonify(res), 200
