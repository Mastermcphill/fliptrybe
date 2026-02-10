from __future__ import annotations

import os

from app.integrations.common import IntegrationDisabledError, IntegrationMisconfiguredError
from app.integrations.messaging.base import MessagingProvider
from app.integrations.messaging.mock_provider import MockMessagingProvider
from app.integrations.messaging.termii_provider import TermiiMessagingProvider, termii_health


def build_messaging_provider(settings, *, channel: str) -> MessagingProvider:
    mode = (getattr(settings, "integrations_mode", "disabled") or "disabled").strip().lower()
    if mode == "disabled":
        raise IntegrationDisabledError(f"INTEGRATION_DISABLED:{channel}")

    ch = (channel or "").strip().lower()
    if ch == "sms" and not bool(getattr(settings, "termii_enabled_sms", False)):
        raise IntegrationDisabledError("INTEGRATION_DISABLED:sms")
    if ch == "whatsapp" and not bool(getattr(settings, "termii_enabled_wa", False)):
        raise IntegrationDisabledError("INTEGRATION_DISABLED:whatsapp")

    provider = (getattr(settings, "payments_provider", "mock") or "mock").strip().lower()
    # Keep one integration mode switch. Mock provider allows deterministic smoke runs.
    if mode == "sandbox" and provider == "mock":
        return MockMessagingProvider()

    api_key = (os.getenv("TERMII_API_KEY") or "").strip()
    sender = (os.getenv("TERMII_SENDER_ID") or "").strip()
    wa_sender = (os.getenv("TERMII_WHATSAPP_SENDER") or sender).strip()
    missing = []
    if not api_key:
        missing.append("TERMII_API_KEY")
    if not sender:
        missing.append("TERMII_SENDER_ID")
    if missing:
        raise IntegrationMisconfiguredError(f"INTEGRATION_MISCONFIGURED:missing {', '.join(missing)}")
    return TermiiMessagingProvider(api_key=api_key, sender_id=sender, whatsapp_sender=wa_sender)


def messaging_health(settings) -> dict:
    mode = (getattr(settings, "integrations_mode", "disabled") or "disabled").strip().lower()
    sms_enabled = bool(getattr(settings, "termii_enabled_sms", False))
    wa_enabled = bool(getattr(settings, "termii_enabled_wa", False))
    env = termii_health()
    missing = env.get("missing", [])
    if mode == "disabled" or (not sms_enabled and not wa_enabled):
        status = "disabled"
    elif missing:
        status = "misconfigured"
    else:
        status = "configured"
    return {
        "status": status,
        "mode": mode,
        "sms_enabled": sms_enabled,
        "wa_enabled": wa_enabled,
        "missing": missing,
    }

