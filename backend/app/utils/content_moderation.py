from __future__ import annotations

import re


CONTACT_BLOCK_MESSAGE = (
    "For safety, contact details cannot be shared in chat. "
    "Please keep communication in FlipTrybe."
)

DESCRIPTION_BLOCK_MESSAGE = (
    "Please remove phone numbers/emails/addresses from description."
)


_PHONE_RE = re.compile(r"(?<!\w)(?:\+?\d[\d\-\s()]{7,}\d)(?!\w)", re.IGNORECASE)
_EMAIL_RE = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)
_WHATSAPP_RE = re.compile(
    r"(?:wa\.me|whatsapp(?:\s+me)?|call\s+me\s+on|dm\s+me\s+on|text\s+me\s+on)",
    re.IGNORECASE,
)
_ADDRESS_RE = re.compile(
    r"\b\d{1,5}\s+[A-Z0-9][A-Z0-9\s,.-]{2,60}\b"
    r"(?:street|st\.|road|rd\.|avenue|ave\.|close|cl\.|lane|ln\.|drive|dr\.|estate|phase)\b",
    re.IGNORECASE,
)
_SHOP_ADDRESS_HINT_RE = re.compile(
    r"(?:shop\s+address|come\s+to\s+my\s+shop|visit\s+our\s+shop|opposite\s+)",
    re.IGNORECASE,
)


def _normalize_text(value: str) -> str:
    return str(value or "").strip()


def contains_contact_details(value: str) -> bool:
    text = _normalize_text(value)
    if not text:
        return False
    if _PHONE_RE.search(text):
        return True
    if _EMAIL_RE.search(text):
        return True
    if _WHATSAPP_RE.search(text):
        return True
    return False


def contains_prohibited_listing_description(value: str) -> bool:
    text = _normalize_text(value)
    if not text:
        return False
    if contains_contact_details(text):
        return True
    if _ADDRESS_RE.search(text):
        return True
    if _SHOP_ADDRESS_HINT_RE.search(text):
        return True
    return False

