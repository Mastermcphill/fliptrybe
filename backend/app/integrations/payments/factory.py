from __future__ import annotations

import os

from app.integrations.common import IntegrationDisabledError, IntegrationMisconfiguredError
from app.integrations.payments.base import PaymentsProvider
from app.integrations.payments.mock_provider import MockPaymentsProvider
from app.integrations.payments.paystack_provider import PaystackPaymentsProvider


def _settings_value(settings, key: str, default=None):
    return getattr(settings, key, default)


def build_payments_provider(settings) -> PaymentsProvider:
    mode = (_settings_value(settings, "integrations_mode", "disabled") or "disabled").strip().lower()
    enabled = bool(_settings_value(settings, "paystack_enabled", False))
    provider = (_settings_value(settings, "payments_provider", "mock") or "mock").strip().lower()

    if mode == "disabled" or not enabled:
        raise IntegrationDisabledError("INTEGRATION_DISABLED:payments")

    if provider == "mock":
        return MockPaymentsProvider()

    if provider != "paystack":
        raise IntegrationMisconfiguredError(f"INTEGRATION_MISCONFIGURED:payments_provider={provider}")

    secret_key = (os.getenv("PAYSTACK_SECRET_KEY") or "").strip()
    if not secret_key:
        raise IntegrationMisconfiguredError("INTEGRATION_MISCONFIGURED:missing PAYSTACK_SECRET_KEY")

    return PaystackPaymentsProvider(secret_key=secret_key)


def payment_health(settings) -> dict:
    mode = (getattr(settings, "integrations_mode", "disabled") or "disabled").strip().lower()
    enabled = bool(getattr(settings, "paystack_enabled", False))
    provider = (getattr(settings, "payments_provider", "mock") or "mock").strip().lower()
    missing = []
    if mode != "disabled" and enabled and provider == "paystack":
        if not (os.getenv("PAYSTACK_SECRET_KEY") or "").strip():
            missing.append("PAYSTACK_SECRET_KEY")
        if not (os.getenv("PAYSTACK_PUBLIC_KEY") or "").strip():
            missing.append("PAYSTACK_PUBLIC_KEY")
    if mode == "disabled" or not enabled:
        status = "disabled"
    elif missing:
        status = "misconfigured"
    else:
        status = "configured"
    return {
        "status": status,
        "mode": mode,
        "provider": provider,
        "enabled": enabled,
        "missing": missing,
    }

