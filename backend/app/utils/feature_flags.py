from __future__ import annotations

import json
from datetime import datetime

from app.extensions import db
from app.models import AutopilotSettings


DEFAULT_FLAGS: dict[str, bool] = {
    "payments.paystack_enabled": False,
    "notifications.termii_enabled": False,
    "media.cloudinary_enabled": False,
    "jobs.autopilot_enabled": True,
    "jobs.escrow_runner_enabled": True,
    "features.moneybox_enabled": True,
}


def _coerce_bool(value, default: bool = False) -> bool:
    if value is None:
        return bool(default)
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return int(value) == 1
    if isinstance(value, str):
        return value.strip().lower() in ("1", "true", "yes", "y", "on")
    return bool(default)


def _settings_json_flags(settings: AutopilotSettings) -> dict[str, bool]:
    raw = getattr(settings, "feature_flags_json", None) or "{}"
    try:
        parsed = json.loads(raw)
    except Exception:
        parsed = {}
    if not isinstance(parsed, dict):
        parsed = {}
    out: dict[str, bool] = {}
    for key, val in parsed.items():
        out[str(key)] = _coerce_bool(val)
    return out


def _resolve_settings(settings: AutopilotSettings | None = None) -> AutopilotSettings:
    if settings is not None:
        return settings
    from app.utils.autopilot import get_settings

    return get_settings()


def get_all_flags(settings: AutopilotSettings | None = None) -> dict[str, bool]:
    s = _resolve_settings(settings)
    json_flags = _settings_json_flags(s)
    flags = dict(DEFAULT_FLAGS)
    flags.update(json_flags)

    # Backward-compatible mapping from existing columns.
    if "payments.paystack_enabled" not in json_flags:
        flags["payments.paystack_enabled"] = _coerce_bool(getattr(s, "paystack_enabled", False), False)
    else:
        flags["payments.paystack_enabled"] = _coerce_bool(
            flags.get("payments.paystack_enabled"),
            _coerce_bool(getattr(s, "paystack_enabled", False), False),
        )
    termii_any = _coerce_bool(getattr(s, "termii_enabled_sms", False), False) or _coerce_bool(
        getattr(s, "termii_enabled_wa", False), False
    )
    if "notifications.termii_enabled" not in json_flags:
        flags["notifications.termii_enabled"] = bool(termii_any)
    else:
        flags["notifications.termii_enabled"] = _coerce_bool(
            flags.get("notifications.termii_enabled"),
            termii_any,
        )
    if "jobs.autopilot_enabled" not in json_flags:
        flags["jobs.autopilot_enabled"] = _coerce_bool(getattr(s, "enabled", True), True)
    else:
        flags["jobs.autopilot_enabled"] = _coerce_bool(
            flags.get("jobs.autopilot_enabled"),
            _coerce_bool(getattr(s, "enabled", True), True),
        )
    return flags


def is_enabled(key: str, *, default: bool = False, settings: AutopilotSettings | None = None) -> bool:
    flags = get_all_flags(settings)
    if key not in flags:
        return bool(default)
    return _coerce_bool(flags.get(key), default)


def update_flags(
    updates: dict[str, object],
    *,
    updated_by: int | None = None,
    settings: AutopilotSettings | None = None,
) -> dict[str, bool]:
    s = _resolve_settings(settings)
    current = get_all_flags(s)
    for key, value in updates.items():
        k = str(key).strip()
        if not k:
            continue
        current[k] = _coerce_bool(value, current.get(k, False))

    # Mirror legacy toggles so existing behavior remains consistent.
    if "payments.paystack_enabled" in current:
        s.paystack_enabled = _coerce_bool(current["payments.paystack_enabled"], bool(getattr(s, "paystack_enabled", False)))
    if "notifications.termii_enabled" in current:
        termii_enabled = _coerce_bool(current["notifications.termii_enabled"], False)
        s.termii_enabled_sms = termii_enabled
        s.termii_enabled_wa = termii_enabled
    if "jobs.autopilot_enabled" in current:
        s.enabled = _coerce_bool(current["jobs.autopilot_enabled"], True)

    s.feature_flags_json = json.dumps(current)
    if updated_by is not None:
        s.payments_mode_changed_by = int(updated_by)
        s.payments_mode_changed_at = datetime.utcnow()
    db.session.add(s)
    db.session.commit()
    return get_all_flags(s)


def public_flag_subset(settings: AutopilotSettings | None = None) -> dict[str, object]:
    s = _resolve_settings(settings)
    flags = get_all_flags(s)
    return {
        "search_v2_mode": (getattr(s, "search_v2_mode", None) or "off"),
        "city_discovery_v1": bool(getattr(s, "city_discovery_v1", True)),
        "views_heat_v1": bool(getattr(s, "views_heat_v1", True)),
        "cart_checkout_v1": bool(getattr(s, "cart_checkout_v1", False)),
        "shortlet_reels_v1": bool(getattr(s, "shortlet_reels_v1", False)),
        "watcher_notifications_v1": bool(getattr(s, "watcher_notifications_v1", False)),
        "features.moneybox_enabled": bool(flags.get("features.moneybox_enabled", True)),
    }
