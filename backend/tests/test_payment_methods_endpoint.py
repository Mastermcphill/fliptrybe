from __future__ import annotations

import unittest

from app import create_app
from app.extensions import db
from app.utils.autopilot import get_settings


class PaymentMethodsEndpointTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()
        cls.client = cls.app.test_client()

    def _set_runtime_mode(
        self,
        *,
        payments_mode: str,
        payments_provider: str = "mock",
        paystack_enabled: bool = False,
    ) -> None:
        with self.app.app_context():
            settings = get_settings()
            settings.payments_mode = payments_mode
            settings.payments_provider = payments_provider
            settings.paystack_enabled = bool(paystack_enabled)
            db.session.add(settings)
            db.session.commit()

    def test_methods_when_paystack_available(self):
        self._set_runtime_mode(
            payments_mode="paystack_auto",
            payments_provider="paystack",
            paystack_enabled=True,
        )
        res = self.client.get("/api/payments/methods?scope=order")
        self.assertEqual(res.status_code, 200)
        body = res.get_json(force=True)
        self.assertTrue(body.get("ok"))
        self.assertTrue(body.get("paystack_available"))
        methods = body.get("methods") or {}
        self.assertTrue(methods.get("wallet", {}).get("available"))
        self.assertTrue(methods.get("paystack_card", {}).get("available"))
        self.assertTrue(methods.get("paystack_transfer", {}).get("available"))
        self.assertFalse(methods.get("bank_transfer_manual", {}).get("available"))

    def test_methods_when_manual_mode(self):
        self._set_runtime_mode(
            payments_mode="manual_company_account",
            payments_provider="paystack",
            paystack_enabled=True,
        )
        res = self.client.get("/api/payments/methods?scope=shortlet")
        self.assertEqual(res.status_code, 200)
        body = res.get_json(force=True)
        self.assertTrue(body.get("ok"))
        self.assertFalse(body.get("paystack_available"))
        methods = body.get("methods") or {}
        self.assertTrue(methods.get("wallet", {}).get("available"))
        self.assertFalse(methods.get("paystack_card", {}).get("available"))
        self.assertFalse(methods.get("paystack_transfer", {}).get("available"))
        self.assertTrue(methods.get("bank_transfer_manual", {}).get("available"))


if __name__ == "__main__":
    unittest.main()
