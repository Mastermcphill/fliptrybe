from __future__ import annotations

from app.integrations.payments.base import PaymentsProvider, PaymentInitializeResult, PaymentVerifyResult


class MockPaymentsProvider(PaymentsProvider):
    name = "mock"

    def initialize(self, *, order_id: int | None, amount: float, email: str, reference: str, metadata: dict | None = None) -> PaymentInitializeResult:
        oid = order_id if order_id is not None else "topup"
        url = f"https://example.com/mock/pay?reference={reference}&order_id={oid}"
        return PaymentInitializeResult(
            authorization_url=url,
            reference=reference,
            provider=self.name,
            raw={
                "order_id": order_id,
                "amount": amount,
                "email": email,
                "metadata": metadata or {},
            },
        )

    def verify(self, reference: str) -> PaymentVerifyResult:
        return PaymentVerifyResult(
            status="success",
            amount=0.0,
            currency="NGN",
            customer="mock",
            raw={"reference": reference, "provider": self.name},
        )

