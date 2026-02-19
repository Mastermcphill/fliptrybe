from __future__ import annotations

import os
import time
import unittest
from unittest.mock import patch

from app import create_app
from app.extensions import db
from app.models import Listing, User
from app.tasks.scale_tasks import process_paystack_webhook_task
from app.utils.jwt_utils import create_token
from app.utils import rate_limit as rate_limit_module


class ScaleRuntimeHardeningTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._saved_env = {
            "SQLALCHEMY_DATABASE_URI": os.getenv("SQLALCHEMY_DATABASE_URI"),
            "DATABASE_URL": os.getenv("DATABASE_URL"),
            "ENABLE_RATE_LIMIT": os.getenv("ENABLE_RATE_LIMIT"),
            "RATE_LIMIT_REDIS_URL": os.getenv("RATE_LIMIT_REDIS_URL"),
            "ENABLE_IDEMPOTENCY_ENFORCEMENT": os.getenv("ENABLE_IDEMPOTENCY_ENFORCEMENT"),
            "PAYSTACK_WEBHOOK_QUEUE": os.getenv("PAYSTACK_WEBHOOK_QUEUE"),
            "TRUST_PROXY_HEADERS": os.getenv("TRUST_PROXY_HEADERS"),
            "RATE_LIMIT_IN_TESTS": os.getenv("RATE_LIMIT_IN_TESTS"),
            "FLIPTRYBE_ENV": os.getenv("FLIPTRYBE_ENV"),
        }
        db_uri = "sqlite:///:memory:"
        os.environ["SQLALCHEMY_DATABASE_URI"] = db_uri
        os.environ["DATABASE_URL"] = db_uri
        os.environ["ENABLE_RATE_LIMIT"] = "true"
        os.environ["RATE_LIMIT_REDIS_URL"] = ""
        os.environ["ENABLE_IDEMPOTENCY_ENFORCEMENT"] = "true"
        os.environ["PAYSTACK_WEBHOOK_QUEUE"] = "true"
        os.environ["TRUST_PROXY_HEADERS"] = "true"
        os.environ["RATE_LIMIT_IN_TESTS"] = "true"
        os.environ["FLIPTRYBE_ENV"] = "dev"
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        cls.client = cls.app.test_client()

    @classmethod
    def tearDownClass(cls):
        for key, value in cls._saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def setUp(self):
        with self.app.app_context():
            db.session.remove()
            db.drop_all()
            db.create_all()
            self._seed_listing_data()
        try:
            rate_limit_module._WINDOWS.clear()  # type: ignore[attr-defined]
            rate_limit_module._CLIENT = None  # type: ignore[attr-defined]
            rate_limit_module._CLIENT_INIT = False  # type: ignore[attr-defined]
        except Exception:
            pass

    def _seed_listing_data(self):
        stamp = str(time.time_ns())
        merchant = User(
            name="Merchant",
            email=f"merchant-{stamp}@fliptrybe.test",
            phone=f"+23490{stamp[-8:]}",
            role="merchant",
            is_verified=True,
        )
        merchant.set_password("Passw0rd!")
        buyer = User(
            name="Buyer",
            email=f"buyer-{stamp}@fliptrybe.test",
            phone=f"+23480{stamp[-8:]}",
            role="buyer",
            is_verified=True,
        )
        buyer.set_password("Passw0rd!")
        db.session.add_all([merchant, buyer])
        db.session.commit()
        listing = Listing(
            user_id=int(merchant.id),
            title="Scale Test Listing",
            description="ready",
            state="Lagos",
            city="Ikeja",
            category="declutter",
            listing_type="declutter",
            price=10000.0,
            base_price=10000.0,
            platform_fee=0.0,
            final_price=10000.0,
            image_path="",
            is_active=True,
        )
        db.session.add(listing)
        db.session.commit()
        self.buyer_id = int(buyer.id)
        self.listing_id = int(listing.id)
        self.buyer_token = create_token(int(buyer.id))

    def test_auth_rate_limit_strict_with_retry_after(self):
        ip_headers = {"X-Forwarded-For": "198.51.100.11"}
        for _ in range(10):
            res = self.client.post(
                "/api/auth/otp/request",
                headers=ip_headers,
                json={"phone": "+2348100002001"},
            )
            self.assertNotEqual(res.status_code, 429)
        blocked = self.client.post(
            "/api/auth/otp/request",
            headers=ip_headers,
            json={"phone": "+2348100002001"},
        )
        self.assertEqual(blocked.status_code, 429)
        payload = blocked.get_json(force=True) or {}
        err = payload.get("error") or {}
        self.assertEqual(err.get("code"), "RATE_LIMITED")
        self.assertGreater(int(err.get("retry_after_seconds") or 0), 0)
        self.assertTrue((blocked.headers.get("Retry-After") or "").strip())

    def test_browse_is_more_lenient_than_writes(self):
        browse_headers = {"X-Forwarded-For": "198.51.100.21"}
        for _ in range(30):
            res = self.client.get("/api/health", headers=browse_headers)
            self.assertNotEqual(res.status_code, 429)

        write_headers = {"X-Forwarded-For": "198.51.100.22"}
        last = None
        for _ in range(61):
            last = self.client.post("/api/listings", headers=write_headers, json={"title": "x"})
        self.assertIsNotNone(last)
        self.assertEqual(last.status_code, 429)
        payload = last.get_json(force=True) or {}
        err = payload.get("error") or {}
        self.assertEqual(err.get("code"), "RATE_LIMITED")
        self.assertTrue((last.headers.get("Retry-After") or "").strip())

    def test_order_create_idempotency_replay_and_reuse_conflict(self):
        headers = {
            "Authorization": f"Bearer {self.buyer_token}",
            "Idempotency-Key": "idem-scale-order-001",
            "X-Forwarded-For": "198.51.100.31",
        }
        payload = {
            "listing_id": int(self.listing_id),
            "amount": 10000,
            "pickup": "Ikeja",
            "dropoff": "Yaba",
        }
        first = self.client.post("/api/orders", headers=headers, json=payload)
        self.assertEqual(first.status_code, 201)
        first_body = first.get_json(force=True) or {}
        first_order = (first_body.get("order") or {}).get("id")
        self.assertTrue(first_order)

        second = self.client.post("/api/orders", headers=headers, json=payload)
        self.assertEqual(second.status_code, 201)
        second_body = second.get_json(force=True) or {}
        second_order = (second_body.get("order") or {}).get("id")
        self.assertEqual(first_order, second_order)

        changed_payload = dict(payload)
        changed_payload["dropoff"] = "Lekki"
        third = self.client.post("/api/orders", headers=headers, json=changed_payload)
        self.assertEqual(third.status_code, 409)
        third_body = third.get_json(force=True) or {}
        error = third_body.get("error") or {}
        self.assertEqual(error.get("code"), "IDEMPOTENCY_KEY_REUSE")

    def test_paystack_webhook_route_enqueues_task(self):
        with patch("app.tasks.scale_tasks.process_paystack_webhook_task.delay") as mocked_delay:
            res = self.client.post(
                "/api/payments/webhook/paystack",
                json={
                    "event": "charge.success",
                    "data": {"reference": "FT-QUEUE-REF-001", "amount": 100000},
                },
            )
            self.assertEqual(res.status_code, 200)
            body = res.get_json(force=True) or {}
            self.assertTrue(bool(body.get("queued")))
            mocked_delay.assert_called_once()

    def test_paystack_webhook_task_is_idempotent_for_same_event(self):
        payload = {
            "id": "evt_test_scale_001",
            "event": "charge.success",
            "data": {"reference": "FT-EVT-001", "amount": 100000},
        }
        with self.app.app_context():
            with patch(
                "app.segments.segment_payments.process_paystack_webhook",
                return_value=({"ok": True, "processed": True}, 200),
            ) as mocked_process:
                first = process_paystack_webhook_task.run(
                    payload=payload,
                    raw_text="{}",
                    signature=None,
                    source="test:webhook",
                    trace_id="trace-1",
                )
                second = process_paystack_webhook_task.run(
                    payload=payload,
                    raw_text="{}",
                    signature=None,
                    source="test:webhook",
                    trace_id="trace-2",
                )
                self.assertTrue(bool(first.get("ok")))
                self.assertTrue(bool(second.get("replayed")))
                self.assertEqual(mocked_process.call_count, 1)


if __name__ == "__main__":
    unittest.main()
