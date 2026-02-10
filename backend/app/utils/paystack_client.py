from __future__ import annotations

import hmac
import hashlib
import os
import requests


def _secret() -> str:
    return os.getenv("PAYSTACK_SECRET_KEY", "").strip()


def verify_signature(raw_body: bytes, signature_header: str | None) -> bool:
    secret = (os.getenv("PAYSTACK_WEBHOOK_SECRET") or _secret()).strip()
    if not secret or not signature_header:
        return False
    digest = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha512).hexdigest()
    return hmac.compare_digest(digest, signature_header.strip())


def initialize_transaction(email: str, amount_ngn: float, reference: str, callback_url: str = "") -> dict:
    secret = _secret()
    if not secret:
        return {"ok": False, "error": "PAYSTACK_SECRET_KEY not set"}
    url = "https://api.paystack.co/transaction/initialize"
    headers = {"Authorization": f"Bearer {secret}", "Content-Type": "application/json"}
    payload = {"email": email, "amount": int(round(float(amount_ngn) * 100)), "reference": reference}
    if callback_url:
        payload["callback_url"] = callback_url
    try:
        r = requests.post(url, headers=headers, json=payload, timeout=20)
        j = r.json() if r.content else {}
        if 200 <= r.status_code < 300 and j.get("status") is True:
            data = j.get("data") or {}
            return {"ok": True, "authorization_url": data.get("authorization_url", ""), "reference": data.get("reference", reference)}
        return {"ok": False, "error": j.get("message") or f"HTTP {r.status_code}"}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def initiate_transfer(amount_ngn: float, recipient_code: str, reference: str) -> dict:
    secret = _secret()
    if not secret:
        return {"ok": False, "error": "PAYSTACK_SECRET_KEY not set"}
    url = "https://api.paystack.co/transfer"
    headers = {"Authorization": f"Bearer {secret}", "Content-Type": "application/json"}
    payload = {"source": "balance", "amount": int(round(float(amount_ngn) * 100)), "recipient": recipient_code, "reference": reference}
    try:
        r = requests.post(url, headers=headers, json=payload, timeout=20)
        j = r.json() if r.content else {}
        if 200 <= r.status_code < 300 and j.get("status") is True:
            data = j.get("data") or {}
            return {"ok": True, "transfer_code": data.get("transfer_code", ""), "reference": reference}
        return {"ok": False, "error": j.get("message") or f"HTTP {r.status_code}"}
    except Exception as e:
        return {"ok": False, "error": str(e)}
