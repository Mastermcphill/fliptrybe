from __future__ import annotations

import os
import requests

from app.integrations.messaging.base import MessagingProvider, MessageResult


TERMII_BASE = "https://api.ng.termii.com/api"


def _map_termii_error(status: int, message: str) -> str:
    msg = (message or "").lower()
    if status == 401 or status == 403:
        return "TERMII_AUTH_FAILED"
    if status == 429:
        return "TERMII_RATE_LIMITED"
    if status == 404:
        return "TERMII_PROVIDER_DOWN"
    if status >= 500:
        return "TERMII_PROVIDER_DOWN"
    if status in (400, 422):
        if "sender" in msg:
            return "TERMII_INVALID_SENDER"
        if "recipient" in msg or "phone" in msg or "to" in msg:
            return "TERMII_INVALID_RECIPIENT"
        return "TERMII_INVALID_RECIPIENT"
    return "TERMII_PROVIDER_DOWN"


class TermiiMessagingProvider(MessagingProvider):
    name = "termii"

    def __init__(self, *, api_key: str, sender_id: str, whatsapp_sender: str):
        self.api_key = api_key
        self.sender_id = sender_id
        self.whatsapp_sender = whatsapp_sender

    def _send(self, *, channel: str, to: str, message: str, sender: str, reference: str = "") -> MessageResult:
        payload = {
            "to": (to or "").strip(),
            "from": sender,
            "sms": message,
            "type": "plain",
            "channel": channel,
            "api_key": self.api_key,
        }
        if reference:
            payload["custom_uid"] = reference[:48]
        try:
            r = requests.post(f"{TERMII_BASE}/sms/send", json=payload, timeout=12)
            data = r.json() if r.content else {}
            if 200 <= r.status_code < 300:
                return MessageResult(ok=True, code="OK", message="sent", raw=data if isinstance(data, dict) else {"payload": data})
            detail = ""
            if isinstance(data, dict):
                detail = str(data.get("message") or data.get("error") or "")
            code = _map_termii_error(r.status_code, detail)
            return MessageResult(
                ok=False,
                code=code,
                message=(detail or f"http_{r.status_code}")[:200],
                raw=data if isinstance(data, dict) else {"payload": data},
            )
        except requests.Timeout:
            return MessageResult(ok=False, code="TERMII_PROVIDER_DOWN", message="timeout")
        except Exception as e:
            return MessageResult(ok=False, code="TERMII_PROVIDER_DOWN", message=str(e)[:200])

    def send_sms(self, *, to: str, message: str, reference: str = "") -> MessageResult:
        return self._send(channel="generic", to=to, message=message, sender=self.sender_id, reference=reference)

    def send_whatsapp(self, *, to: str, message: str, reference: str = "") -> MessageResult:
        sender = self.whatsapp_sender or self.sender_id
        return self._send(channel="whatsapp", to=to, message=message, sender=sender, reference=reference)


def termii_health() -> dict:
    missing = []
    if not (os.getenv("TERMII_API_KEY") or "").strip():
        missing.append("TERMII_API_KEY")
    if not (os.getenv("TERMII_SENDER_ID") or "").strip():
        missing.append("TERMII_SENDER_ID")
    return {"missing": missing}

