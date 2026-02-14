from __future__ import annotations

import os
import time
import unittest
from datetime import datetime, timedelta

from app import create_app
from app.extensions import db
from app.models import Listing, Order, PayoutRequest, User, WalletTxn
from app.utils.jwt_utils import create_token


class AutopilotDraftEndpointsTestCase(unittest.TestCase):
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

    def _seed_user(self, role: str) -> User:
        suffix = str(time.time_ns())
        row = User(
            name=f"{role}-{suffix[-5:]}",
            email=f"{role}-{suffix}@fliptrybe.test",
            phone=f"081{suffix[-8:]}",
            role=role,
            is_verified=True,
        )
        row.set_password("Passw0rd!")
        db.session.add(row)
        db.session.commit()
        return row

    def _seed_orders_for_autopilot(self):
        buyer = self._seed_user("buyer")
        merchant = self._seed_user("merchant")
        listing = Listing(
            user_id=int(merchant.id),
            title="Laptop",
            description="Core i7",
            category="declutter",
            city="Lagos",
            state="Lagos",
            price=35000.0,
            final_price=35000.0,
            base_price=35000.0,
            platform_fee=1750.0,
            is_active=True,
            created_at=datetime.utcnow() - timedelta(days=3),
        )
        db.session.add(listing)
        db.session.flush()
        for _ in range(50):
            db.session.add(
                Order(
                    buyer_id=int(buyer.id),
                    merchant_id=int(merchant.id),
                    listing_id=int(listing.id),
                    amount=35000.0,
                    total_price=35000.0,
                    status="paid",
                    created_at=datetime.utcnow() - timedelta(days=2),
                    updated_at=datetime.utcnow() - timedelta(days=2),
                )
            )
        db.session.add(
            PayoutRequest(
                user_id=int(merchant.id),
                amount=200000.0,
                status="pending",
                created_at=datetime.utcnow() - timedelta(days=1),
            )
        )
        db.session.commit()

    def test_generate_draft_idempotency(self):
        with self.app.app_context():
            admin = self._seed_user("admin")
            self._seed_orders_for_autopilot()
            token = create_token(int(admin.id))
        headers = {"Authorization": f"Bearer {token}"}

        run_res = self.client.post("/api/admin/autopilot/run?window=30", headers=headers, json={})
        self.assertEqual(run_res.status_code, 200)
        run_payload = run_res.get_json(force=True) or {}
        recommendations = run_payload.get("recommendations") or []
        self.assertGreaterEqual(len(recommendations), 1)
        rec_id = int(recommendations[0]["id"])

        accept_res = self.client.post(
            f"/api/admin/autopilot/recommendations/{rec_id}/status",
            headers=headers,
            json={"status": "accepted"},
        )
        self.assertEqual(accept_res.status_code, 200)

        draft_res = self.client.post(
            "/api/admin/autopilot/generate-draft?window=30",
            headers=headers,
            json={"accepted_only": True},
        )
        self.assertEqual(draft_res.status_code, 200)
        first = draft_res.get_json(force=True) or {}
        policy_id = int((first.get("policy") or {}).get("id") or 0)
        self.assertGreater(policy_id, 0)

        second_res = self.client.post(
            "/api/admin/autopilot/generate-draft?window=30",
            headers=headers,
            json={"accepted_only": True},
        )
        self.assertEqual(second_res.status_code, 200)
        second = second_res.get_json(force=True) or {}
        self.assertEqual(int((second.get("policy") or {}).get("id") or 0), policy_id)
        self.assertTrue(second.get("idempotent"))

    def test_preview_impact_no_ledger_write(self):
        with self.app.app_context():
            admin = self._seed_user("admin")
            self._seed_orders_for_autopilot()
            token = create_token(int(admin.id))
        headers = {"Authorization": f"Bearer {token}"}

        run_res = self.client.post("/api/admin/autopilot/run?window=30", headers=headers, json={})
        rec_id = int(((run_res.get_json(force=True) or {}).get("recommendations") or [{}])[0].get("id") or 0)
        self.client.post(
            f"/api/admin/autopilot/recommendations/{rec_id}/status",
            headers=headers,
            json={"status": "accepted"},
        )
        draft_res = self.client.post(
            "/api/admin/autopilot/generate-draft?window=30",
            headers=headers,
            json={"accepted_only": True},
        )
        draft_payload = draft_res.get_json(force=True) or {}
        policy_id = int(((draft_payload.get("policy") or {}).get("id") or 0))
        if policy_id <= 0:
            policy_id = int(draft_payload.get("existing_policy_id") or 0)
        self.assertGreater(policy_id, 0)

        with self.app.app_context():
            before = WalletTxn.query.count()
        preview_res = self.client.post(
            "/api/admin/autopilot/preview-impact",
            headers=headers,
            json={"draft_policy_id": policy_id},
        )
        self.assertEqual(preview_res.status_code, 200)
        payload = preview_res.get_json(force=True) or {}
        self.assertTrue(payload.get("ok"))
        self.assertIn("projected_revenue_delta_minor", payload)
        self.assertIn("liquidity_effect", payload)
        with self.app.app_context():
            after = WalletTxn.query.count()
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
