from __future__ import annotations

import os

from app.integrations.messaging.base import MessagingProvider, MessageResult


class MockMessagingProvider(MessagingProvider):
    name = "mock"

    def _force_failure(self, message: str) -> bool:
        msg = (message or "").lower()
        return "[fail]" in msg or (os.getenv("MOCK_NOTIFY_FORCE_FAIL") or "").strip() == "1"

    def send_sms(self, *, to: str, message: str, reference: str = "") -> MessageResult:
        if self._force_failure(message):
            return MessageResult(ok=False, code="TERMII_PROVIDER_DOWN", message="mock forced failure")
        return MessageResult(ok=True, code="OK", message="mock_sent", raw={"to": to, "reference": reference})

    def send_whatsapp(self, *, to: str, message: str, reference: str = "") -> MessageResult:
        if self._force_failure(message):
            return MessageResult(ok=False, code="TERMII_PROVIDER_DOWN", message="mock forced failure")
        return MessageResult(ok=True, code="OK", message="mock_sent", raw={"to": to, "reference": reference})

