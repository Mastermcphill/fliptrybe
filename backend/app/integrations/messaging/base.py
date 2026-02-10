from __future__ import annotations

from dataclasses import dataclass


@dataclass
class MessageResult:
    ok: bool
    code: str = ""
    message: str = ""
    raw: dict | None = None


class MessagingProvider:
    name = "unknown"

    def send_sms(self, *, to: str, message: str, reference: str = "") -> MessageResult:
        raise NotImplementedError

    def send_whatsapp(self, *, to: str, message: str, reference: str = "") -> MessageResult:
        raise NotImplementedError

