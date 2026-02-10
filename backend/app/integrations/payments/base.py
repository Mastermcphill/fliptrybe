from __future__ import annotations

from dataclasses import dataclass


@dataclass
class PaymentInitializeResult:
    authorization_url: str
    reference: str
    provider: str
    raw: dict | None = None


@dataclass
class PaymentVerifyResult:
    status: str
    amount: float
    currency: str
    customer: str
    raw: dict | None = None


class PaymentsProvider:
    name = "unknown"

    def initialize(self, *, order_id: int | None, amount: float, email: str, reference: str, metadata: dict | None = None) -> PaymentInitializeResult:
        raise NotImplementedError

    def verify(self, reference: str) -> PaymentVerifyResult:
        raise NotImplementedError

