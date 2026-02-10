from __future__ import annotations

import os
import requests

from app.integrations.payments.base import PaymentsProvider, PaymentInitializeResult, PaymentVerifyResult


class PaystackPaymentsProvider(PaymentsProvider):
    name = "paystack"

    def __init__(self, secret_key: str):
        self.secret_key = secret_key

    def initialize(self, *, order_id: int | None, amount: float, email: str, reference: str, metadata: dict | None = None) -> PaymentInitializeResult:
        payload = {
            "email": email,
            "amount": int(round(float(amount) * 100)),
            "reference": reference,
            "metadata": metadata or {},
        }
        callback_url = (os.getenv("PAYSTACK_CALLBACK_URL") or "").strip()
        if callback_url:
            payload["callback_url"] = callback_url
        headers = {
            "Authorization": f"Bearer {self.secret_key}",
            "Content-Type": "application/json",
        }
        r = requests.post("https://api.paystack.co/transaction/initialize", headers=headers, json=payload, timeout=25)
        j = r.json() if r.content else {}
        if r.status_code < 200 or r.status_code >= 300 or j.get("status") is not True:
            msg = (j.get("message") or f"HTTP {r.status_code}").strip()
            raise RuntimeError(f"PAYSTACK_INIT_FAILED:{msg}")
        data = j.get("data") or {}
        return PaymentInitializeResult(
            authorization_url=(data.get("authorization_url") or "").strip(),
            reference=(data.get("reference") or reference).strip(),
            provider=self.name,
            raw=j if isinstance(j, dict) else {"payload": j},
        )

    def verify(self, reference: str) -> PaymentVerifyResult:
        ref = (reference or "").strip()
        headers = {
            "Authorization": f"Bearer {self.secret_key}",
            "Content-Type": "application/json",
        }
        r = requests.get(f"https://api.paystack.co/transaction/verify/{ref}", headers=headers, timeout=25)
        j = r.json() if r.content else {}
        if r.status_code < 200 or r.status_code >= 300 or j.get("status") is not True:
            msg = (j.get("message") or f"HTTP {r.status_code}").strip()
            raise RuntimeError(f"PAYSTACK_VERIFY_FAILED:{msg}")
        data = j.get("data") or {}
        amount_kobo = data.get("amount") or 0
        try:
            amount = float(amount_kobo) / 100.0
        except Exception:
            amount = 0.0
        customer_email = ((data.get("customer") or {}).get("email") or "").strip()
        return PaymentVerifyResult(
            status=(data.get("status") or "").strip().lower(),
            amount=amount,
            currency=(data.get("currency") or "NGN").strip().upper(),
            customer=customer_email,
            raw=j if isinstance(j, dict) else {"payload": j},
        )

