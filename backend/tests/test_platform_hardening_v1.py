from __future__ import annotations

import json
import os
import time
import unittest
from datetime import datetime

from app import create_app
from app.extensions import db
from app.jobs.escrow_runner import run_escrow_automation
from app.models import (
    AutopilotSettings,
    JobRun,
    Listing,
    PlatformEvent,
    User,
)
from app.utils.events import log_event
from app.utils.jwt_utils import create_token


class PlatformHardeningV1TestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._old_db_uri = os.environ.get("SQLALCHEMY_DATABASE_URI")
        os.environ["SQLALCHEMY_DATABASE_URI"] = "sqlite:///:memory:"
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()
        cls.client = cls.app.test_client()

    @classmethod
    def tearDownClass(cls):
        if cls._old_db_uri is None:
            os.environ.pop("SQLALCHEMY_DATABASE_URI", None)
        else:
            os.environ["SQLALCHEMY_DATABASE_URI"] = cls._old_db_uri

    def _unique(self) -> str:
        return str(time.time_ns())

    def _create_user(self, *, role: str = "buyer", verified: bool = True) -> User:
        suffix = self._unique()
        user = User(
            name=f"{role.title()} {suffix[-5:]}",
            email=f"{role}-{suffix}@fliptrybe.test",
            phone=f"080{suffix[-8:]}",
            role=role,
            is_verified=bool(verified),
        )
        user.set_password("Passw0rd!")
        db.session.add(user)
        db.session.commit()
        return user

    def test_event_logger_idempotency_and_safe_metadata(self):
        key = f"event-idempotency-{self._unique()}"
        with self.app.app_context():
            first = log_event(
                "unit_test_event",
                idempotency_key=key,
                metadata={"when": datetime.utcnow(), "tags": {"a", "b"}, "nested": {"v": 1}},
            )
            second = log_event(
                "unit_test_event",
                idempotency_key=key,
                metadata={"when": datetime.utcnow(), "tags": {"c"}, "nested": {"v": 2}},
            )
            self.assertIsNotNone(first)
            self.assertIsNotNone(second)
            rows = PlatformEvent.query.filter_by(idempotency_key=key).all()
            self.assertEqual(len(rows), 1)
            payload = rows[0].metadata_dict()
            self.assertIsInstance(payload, dict)
            self.assertIn("nested", payload)

    def test_order_and_role_flows_emit_platform_events(self):
        with self.app.app_context():
            merchant = self._create_user(role="merchant", verified=True)
            buyer = self._create_user(role="buyer", verified=True)
            role_user = self._create_user(role="buyer", verified=True)
            listing = Listing(
                user_id=int(merchant.id),
                title="Event Log Listing",
                description="Event instrumentation test",
                category="declutter",
                price=10000.0,
                base_price=10000.0,
                platform_fee=0.0,
                final_price=10000.0,
                state="Lagos",
                city="Ikeja",
                image_path="",
                date_posted=datetime.utcnow(),
            )
            db.session.add(listing)
            db.session.commit()
            listing_id = int(listing.id)
            buyer_token = create_token(int(buyer.id))
            role_token = create_token(int(role_user.id))

        order_res = self.client.post(
            "/api/orders",
            headers={"Authorization": f"Bearer {buyer_token}"},
            json={
                "listing_id": listing_id,
                "amount": 10000,
                "delivery_fee": 0,
                "inspection_fee": 0,
                "pickup": "Ikeja",
                "dropoff": "Yaba",
            },
        )
        self.assertEqual(order_res.status_code, 201)
        order_body = order_res.get_json(force=True) or {}
        order = order_body.get("order") or {}
        order_id = int(order.get("id"))
        self.assertGreater(order_id, 0)

        role_res = self.client.post(
            "/api/role-requests",
            headers={"Authorization": f"Bearer {role_token}"},
            json={"requested_role": "merchant", "reason": "platform_hardening_test"},
        )
        self.assertEqual(role_res.status_code, 201)

        with self.app.app_context():
            order_event = PlatformEvent.query.filter_by(
                event_type="order_created",
                subject_type="order",
                subject_id=str(order_id),
            ).first()
            self.assertIsNotNone(order_event)
            role_event = PlatformEvent.query.filter_by(
                event_type="role_request_submitted",
                subject_type="role_request",
            ).order_by(PlatformEvent.id.desc()).first()
            self.assertIsNotNone(role_event)

    def test_health_summary_contract_and_feature_flag_enforcement(self):
        with self.app.app_context():
            admin = self._create_user(role="admin", verified=True)
            admin_token = create_token(int(admin.id))

            settings = AutopilotSettings.query.first()
            if not settings:
                settings = AutopilotSettings(enabled=True)
            settings.payments_mode = "paystack_auto"
            settings.payments_provider = "paystack"
            settings.paystack_enabled = True
            settings.feature_flags_json = json.dumps(
                {
                    "payments.paystack_enabled": False,
                    "jobs.escrow_runner_enabled": False,
                }
            )
            db.session.add(settings)
            db.session.commit()

        methods_res = self.client.get("/api/payments/methods?scope=order")
        self.assertEqual(methods_res.status_code, 200)
        methods_payload = methods_res.get_json(force=True) or {}
        self.assertFalse(bool(methods_payload.get("paystack_available")))

        health_res = self.client.get(
            "/api/admin/health/summary",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        self.assertEqual(health_res.status_code, 200)
        health = health_res.get_json(force=True) or {}
        required_keys = [
            "server_time",
            "git_sha",
            "alembic_head",
            "notify_queue_pending",
            "notify_queue_failed",
            "escrow_runner_last_run_at",
            "escrow_pending_settlements_count",
            "payouts_pending_count",
            "events_last_1h_errors",
            "events_last_24h_errors",
            "paystack_mode",
            "termii_enabled",
            "cloudinary_enabled",
        ]
        for key in required_keys:
            self.assertIn(key, health)

        with self.app.app_context():
            disabled_result = run_escrow_automation(limit=1)
            self.assertFalse(bool(disabled_result.get("ok", True)))
            self.assertTrue(bool(disabled_result.get("disabled")))
            disabled_run = (
                JobRun.query.filter_by(job_name="escrow_runner")
                .order_by(JobRun.id.desc())
                .first()
            )
            self.assertIsNotNone(disabled_run)
            self.assertFalse(bool(disabled_run.ok))

            settings = AutopilotSettings.query.first()
            settings.feature_flags_json = json.dumps({"jobs.escrow_runner_enabled": True})
            db.session.add(settings)
            db.session.commit()

            enabled_result = run_escrow_automation(limit=1)
            self.assertTrue(bool(enabled_result.get("ok")))
            enabled_run = (
                JobRun.query.filter_by(job_name="escrow_runner")
                .order_by(JobRun.id.desc())
                .first()
            )
            self.assertIsNotNone(enabled_run)
            self.assertTrue(bool(enabled_run.ok))


if __name__ == "__main__":
    unittest.main()
