from __future__ import annotations

import json
import os
from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, AuditLog
from app.utils.jwt_utils import decode_token
from app.utils.autopilot import get_settings, tick
from app.integrations.payments.factory import payment_health
from app.integrations.messaging.factory import messaging_health

autopilot_bp = Blueprint("autopilot_bp", __name__, url_prefix="/api/admin/autopilot")
payments_settings_bp = Blueprint("payments_settings_bp", __name__, url_prefix="/api/admin/settings")

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
        "payments_mode": base.get("payments_mode") or "mock",
        "paystack_enabled": base.get("paystack_enabled"),
        "termii_enabled_sms": base.get("termii_enabled_sms"),
        "termii_enabled_wa": base.get("termii_enabled_wa"),
        "integrations_mode": base.get("integrations_mode"),
        "manual_payment_bank_name": base.get("manual_payment_bank_name") or "",
        "manual_payment_account_number": base.get("manual_payment_account_number") or "",
        "manual_payment_account_name": base.get("manual_payment_account_name") or "",
        "manual_payment_note": base.get("manual_payment_note") or "",
        "manual_payment_sla_minutes": int(base.get("manual_payment_sla_minutes") or 360),
    }
    base["integration_health"] = {
        "payments": p_health,
        "messaging": m_health,
    }
    base["features"] = {
        "search_v2_mode": (getattr(s, "search_v2_mode", None) or "off"),
        "payments_allow_legacy_fallback": bool(getattr(s, "payments_allow_legacy_fallback", False)),
        "otel_enabled": bool(getattr(s, "otel_enabled", False)),
        "rate_limit_enabled": bool(getattr(s, "rate_limit_enabled", True)),
        "city_discovery_v1": bool(getattr(s, "city_discovery_v1", True)),
        "views_heat_v1": bool(getattr(s, "views_heat_v1", True)),
        "cart_checkout_v1": bool(getattr(s, "cart_checkout_v1", False)),
        "shortlet_reels_v1": bool(getattr(s, "shortlet_reels_v1", False)),
        "watcher_notifications_v1": bool(getattr(s, "watcher_notifications_v1", False)),
    }
    return base


def _coerce_sla_minutes(value, default_value: int) -> int:
    if value is None:
        return int(default_value)
    try:
        parsed = int(value)
    except Exception:
        parsed = int(default_value)
    if parsed < 5:
        parsed = 5
    if parsed > 10080:
        parsed = 10080
    return parsed


def _payments_mode(s) -> str:
    mode = (getattr(s, "payments_mode", None) or "").strip().lower()
    if mode in ("paystack_auto", "manual_company_account", "mock"):
        return mode
    provider = (getattr(s, "payments_provider", "mock") or "mock").strip().lower()
    return "mock" if provider == "mock" else "paystack_auto"


def _payments_health_payload(s) -> dict:
    mode = _payments_mode(s)
    paystack_secret_present = bool((os.getenv("PAYSTACK_SECRET_KEY") or "").strip())
    paystack_public_present = bool((os.getenv("PAYSTACK_PUBLIC_KEY") or "").strip())
    paystack_webhook_secret_present = bool((os.getenv("PAYSTACK_WEBHOOK_SECRET") or "").strip())
    missing_keys = []
    if mode == "paystack_auto":
        if not paystack_secret_present:
            missing_keys.append("PAYSTACK_SECRET_KEY")
        if not paystack_public_present:
            missing_keys.append("PAYSTACK_PUBLIC_KEY")
        if not paystack_webhook_secret_present and not paystack_secret_present:
            missing_keys.append("PAYSTACK_WEBHOOK_SECRET")
    return {
        "mode": mode,
        "paystack_secret_present": paystack_secret_present,
        "paystack_public_present": paystack_public_present,
        "paystack_webhook_secret_present": paystack_webhook_secret_present,
        "missing_keys": missing_keys,
        "last_paystack_webhook_at": s.last_paystack_webhook_at.isoformat() if getattr(s, "last_paystack_webhook_at", None) else None,
        "misconfigured": bool(mode == "paystack_auto" and missing_keys),
    }


def _payments_audit_payload(s) -> dict:
    changed_by_id = getattr(s, "payments_mode_changed_by", None)
    changed_by_email = None
    if changed_by_id is not None:
        try:
            actor = db.session.get(User, int(changed_by_id))
            if actor:
                changed_by_email = getattr(actor, "email", None)
        except Exception:
            changed_by_email = None
    return {
        "last_changed_at": s.payments_mode_changed_at.isoformat() if getattr(s, "payments_mode_changed_at", None) else None,
        "last_changed_by": int(changed_by_id) if changed_by_id is not None else None,
        "last_changed_by_email": changed_by_email,
    }


def _save_payments_mode_audit(*, actor_id: int | None, old_mode: str, new_mode: str) -> None:
    try:
        db.session.add(
            AuditLog(
                actor_user_id=actor_id,
                action="payments_mode_changed",
                target_type="autopilot_settings",
                target_id=1,
                meta=json.dumps({"from": old_mode, "to": new_mode}),
            )
        )
        db.session.commit()
    except Exception:
        db.session.rollback()


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
    incoming_search_mode = (data.get("search_v2_mode") or "").strip().lower()
    if incoming_search_mode and incoming_search_mode not in ("off", "shadow", "on"):
        return jsonify({"ok": False, "message": "search_v2_mode must be off|shadow|on"}), 400

    s.integrations_mode = mode
    s.payments_provider = provider
    s.paystack_enabled = _as_bool(data.get("paystack_enabled"), bool(s.paystack_enabled))
    s.termii_enabled_sms = _as_bool(data.get("termii_enabled_sms"), bool(s.termii_enabled_sms))
    s.termii_enabled_wa = _as_bool(data.get("termii_enabled_wa"), bool(s.termii_enabled_wa))
    if incoming_search_mode:
        s.search_v2_mode = incoming_search_mode
    s.payments_allow_legacy_fallback = _as_bool(
        data.get("payments_allow_legacy_fallback"),
        bool(getattr(s, "payments_allow_legacy_fallback", False)),
    )
    s.otel_enabled = _as_bool(data.get("otel_enabled"), bool(getattr(s, "otel_enabled", False)))
    s.rate_limit_enabled = _as_bool(data.get("rate_limit_enabled"), bool(getattr(s, "rate_limit_enabled", True)))
    s.city_discovery_v1 = _as_bool(data.get("city_discovery_v1"), bool(getattr(s, "city_discovery_v1", True)))
    s.views_heat_v1 = _as_bool(data.get("views_heat_v1"), bool(getattr(s, "views_heat_v1", True)))
    s.cart_checkout_v1 = _as_bool(data.get("cart_checkout_v1"), bool(getattr(s, "cart_checkout_v1", False)))
    s.shortlet_reels_v1 = _as_bool(data.get("shortlet_reels_v1"), bool(getattr(s, "shortlet_reels_v1", False)))
    s.watcher_notifications_v1 = _as_bool(data.get("watcher_notifications_v1"), bool(getattr(s, "watcher_notifications_v1", False)))
    if "manual_payment_bank_name" in data:
        s.manual_payment_bank_name = str(data.get("manual_payment_bank_name") or "").strip()[:120]
    if "manual_payment_account_number" in data:
        s.manual_payment_account_number = str(data.get("manual_payment_account_number") or "").strip()[:64]
    if "manual_payment_account_name" in data:
        s.manual_payment_account_name = str(data.get("manual_payment_account_name") or "").strip()[:120]
    if "manual_payment_note" in data:
        s.manual_payment_note = str(data.get("manual_payment_note") or "").strip()[:240]
    if "manual_payment_sla_minutes" in data:
        s.manual_payment_sla_minutes = _coerce_sla_minutes(
            data.get("manual_payment_sla_minutes"),
            int(getattr(s, "manual_payment_sla_minutes", 360) or 360),
        )
    incoming_payments_mode = (data.get("payments_mode") or "").strip().lower()
    mode_changed = False
    old_mode = _payments_mode(s)
    if incoming_payments_mode:
        if incoming_payments_mode not in ("paystack_auto", "manual_company_account", "mock"):
            return jsonify({"ok": False, "message": "payments_mode must be paystack_auto|manual_company_account|mock"}), 400
        s.payments_mode = incoming_payments_mode
        s.payments_mode_changed_at = datetime.utcnow()
        s.payments_mode_changed_by = int(u.id)
        mode_changed = old_mode != incoming_payments_mode
    db.session.add(s)
    db.session.commit()
    if mode_changed:
        _save_payments_mode_audit(actor_id=int(u.id), old_mode=old_mode, new_mode=incoming_payments_mode)
    return jsonify({"ok": True, "settings": _settings_payload(s)}), 200


@autopilot_bp.post("/tick")
def manual_tick():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    res = tick()
    return jsonify(res), 200


@payments_settings_bp.get("/payments")
def get_payments_settings():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    s = get_settings()
    payload = {
        "mode": _payments_mode(s),
        "paystack_enabled": bool(getattr(s, "paystack_enabled", False)),
        "integrations_mode": (getattr(s, "integrations_mode", "disabled") or "disabled"),
        "payments_provider": (getattr(s, "payments_provider", "mock") or "mock"),
        "payments_allow_legacy_fallback": bool(getattr(s, "payments_allow_legacy_fallback", False)),
        "search_v2_mode": (getattr(s, "search_v2_mode", None) or "off"),
        "otel_enabled": bool(getattr(s, "otel_enabled", False)),
        "rate_limit_enabled": bool(getattr(s, "rate_limit_enabled", True)),
        "city_discovery_v1": bool(getattr(s, "city_discovery_v1", True)),
        "views_heat_v1": bool(getattr(s, "views_heat_v1", True)),
        "cart_checkout_v1": bool(getattr(s, "cart_checkout_v1", False)),
        "shortlet_reels_v1": bool(getattr(s, "shortlet_reels_v1", False)),
        "watcher_notifications_v1": bool(getattr(s, "watcher_notifications_v1", False)),
        "manual_payment_bank_name": (getattr(s, "manual_payment_bank_name", "") or ""),
        "manual_payment_account_number": (getattr(s, "manual_payment_account_number", "") or ""),
        "manual_payment_account_name": (getattr(s, "manual_payment_account_name", "") or ""),
        "manual_payment_note": (getattr(s, "manual_payment_note", "") or ""),
        "manual_payment_sla_minutes": int(getattr(s, "manual_payment_sla_minutes", 360) or 360),
        "health": _payments_health_payload(s),
        "audit": _payments_audit_payload(s),
    }
    return jsonify({"ok": True, "settings": payload}), 200


@payments_settings_bp.post("/payments")
def set_payments_settings():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    data = request.get_json(silent=True) or {}
    mode = (data.get("mode") or "").strip().lower()
    if mode not in ("paystack_auto", "manual_company_account", "mock"):
        return jsonify({"ok": False, "message": "mode must be paystack_auto|manual_company_account|mock"}), 400

    s = get_settings()
    old_mode = _payments_mode(s)
    search_mode = (data.get("search_v2_mode") or "").strip().lower()
    if search_mode and search_mode not in ("off", "shadow", "on"):
        return jsonify({"ok": False, "message": "search_v2_mode must be off|shadow|on"}), 400
    s.payments_mode = mode
    s.payments_mode_changed_at = datetime.utcnow()
    s.payments_mode_changed_by = int(u.id)
    if mode == "mock":
        s.payments_provider = "mock"
    elif mode == "paystack_auto" and (getattr(s, "payments_provider", "mock") or "mock").strip().lower() == "mock":
        s.payments_provider = "paystack"
    db.session.add(s)
    if search_mode:
        s.search_v2_mode = search_mode
    if "payments_allow_legacy_fallback" in data:
        s.payments_allow_legacy_fallback = _as_bool(
            data.get("payments_allow_legacy_fallback"),
            bool(getattr(s, "payments_allow_legacy_fallback", False)),
        )
    if "otel_enabled" in data:
        s.otel_enabled = _as_bool(data.get("otel_enabled"), bool(getattr(s, "otel_enabled", False)))
    if "rate_limit_enabled" in data:
        s.rate_limit_enabled = _as_bool(data.get("rate_limit_enabled"), bool(getattr(s, "rate_limit_enabled", True)))
    if "city_discovery_v1" in data:
        s.city_discovery_v1 = _as_bool(data.get("city_discovery_v1"), bool(getattr(s, "city_discovery_v1", True)))
    if "views_heat_v1" in data:
        s.views_heat_v1 = _as_bool(data.get("views_heat_v1"), bool(getattr(s, "views_heat_v1", True)))
    if "cart_checkout_v1" in data:
        s.cart_checkout_v1 = _as_bool(data.get("cart_checkout_v1"), bool(getattr(s, "cart_checkout_v1", False)))
    if "shortlet_reels_v1" in data:
        s.shortlet_reels_v1 = _as_bool(data.get("shortlet_reels_v1"), bool(getattr(s, "shortlet_reels_v1", False)))
    if "watcher_notifications_v1" in data:
        s.watcher_notifications_v1 = _as_bool(data.get("watcher_notifications_v1"), bool(getattr(s, "watcher_notifications_v1", False)))
    if "manual_payment_bank_name" in data:
        s.manual_payment_bank_name = str(data.get("manual_payment_bank_name") or "").strip()[:120]
    if "manual_payment_account_number" in data:
        s.manual_payment_account_number = str(data.get("manual_payment_account_number") or "").strip()[:64]
    if "manual_payment_account_name" in data:
        s.manual_payment_account_name = str(data.get("manual_payment_account_name") or "").strip()[:120]
    if "manual_payment_note" in data:
        s.manual_payment_note = str(data.get("manual_payment_note") or "").strip()[:240]
    if "manual_payment_sla_minutes" in data:
        s.manual_payment_sla_minutes = _coerce_sla_minutes(
            data.get("manual_payment_sla_minutes"),
            int(getattr(s, "manual_payment_sla_minutes", 360) or 360),
        )
    db.session.commit()
    if old_mode != mode:
        _save_payments_mode_audit(actor_id=int(u.id), old_mode=old_mode, new_mode=mode)

    payload = {
        "mode": _payments_mode(s),
        "paystack_enabled": bool(getattr(s, "paystack_enabled", False)),
        "integrations_mode": (getattr(s, "integrations_mode", "disabled") or "disabled"),
        "payments_provider": (getattr(s, "payments_provider", "mock") or "mock"),
        "payments_allow_legacy_fallback": bool(getattr(s, "payments_allow_legacy_fallback", False)),
        "search_v2_mode": (getattr(s, "search_v2_mode", None) or "off"),
        "otel_enabled": bool(getattr(s, "otel_enabled", False)),
        "rate_limit_enabled": bool(getattr(s, "rate_limit_enabled", True)),
        "city_discovery_v1": bool(getattr(s, "city_discovery_v1", True)),
        "views_heat_v1": bool(getattr(s, "views_heat_v1", True)),
        "cart_checkout_v1": bool(getattr(s, "cart_checkout_v1", False)),
        "shortlet_reels_v1": bool(getattr(s, "shortlet_reels_v1", False)),
        "watcher_notifications_v1": bool(getattr(s, "watcher_notifications_v1", False)),
        "manual_payment_bank_name": (getattr(s, "manual_payment_bank_name", "") or ""),
        "manual_payment_account_number": (getattr(s, "manual_payment_account_number", "") or ""),
        "manual_payment_account_name": (getattr(s, "manual_payment_account_name", "") or ""),
        "manual_payment_note": (getattr(s, "manual_payment_note", "") or ""),
        "manual_payment_sla_minutes": int(getattr(s, "manual_payment_sla_minutes", 360) or 360),
        "health": _payments_health_payload(s),
        "audit": _payments_audit_payload(s),
    }
    return jsonify({"ok": True, "settings": payload}), 200
