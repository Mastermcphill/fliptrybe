from __future__ import annotations

import os
import time
import unittest
from datetime import datetime, timedelta

from app import create_app
from app.extensions import db
from app.models import Listing, Order, PayoutRequest, User, WalletTxn
from app.models.risk import Dispute
from app.services.autopilot.recommender import generate_recommendations
from app.services.autopilot.signals import compute_autopilot_signals


class AutopilotRecommenderTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._old_db_uri = os.environ.get("SQLALCHEMY_DATABASE_URI")
        os.environ["SQLALCHEMY_DATABASE_URI"] = "sqlite:///:memory:"
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()

    @classmethod
    def tearDownClass(cls):
        if cls._old_db_uri is None:
            os.environ.pop("SQLALCHEMY_DATABASE_URI", None)
        else:
            os.environ["SQLALCHEMY_DATABASE_URI"] = cls._old_db_uri

    def _seed_user(self, role: str) -> User:
        suffix = str(time.time_ns())
        row = User(
            name=f"{role}-{suffix[-6:]}",
            email=f"{role}-{suffix}@fliptrybe.test",
            phone=f"080{suffix[-8:]}",
            role=role,
            is_verified=True,
        )
        row.set_password("Passw0rd!")
        db.session.add(row)
        db.session.commit()
        return row

    def test_signals_return_segmented_metrics(self):
        with self.app.app_context():
            buyer = self._seed_user("buyer")
            merchant = self._seed_user("merchant")
            listing = Listing(
                user_id=int(merchant.id),
                title="iPhone 12",
                description="Good condition",
                category="declutter",
                city="Lagos",
                state="Lagos",
                price=15000.0,
                final_price=15000.0,
                base_price=15000.0,
                platform_fee=750.0,
                is_active=True,
                created_at=datetime.utcnow() - timedelta(days=2),
            )
            db.session.add(listing)
            db.session.flush()
            for idx in range(35):
                order = Order(
                    buyer_id=int(buyer.id),
                    merchant_id=int(merchant.id),
                    listing_id=int(listing.id),
                    amount=15000.0,
                    total_price=15000.0,
                    status="paid",
                    created_at=datetime.utcnow() - timedelta(days=1),
                    updated_at=datetime.utcnow() - timedelta(days=1),
                )
                db.session.add(order)
            db.session.add(
                PayoutRequest(
                    user_id=int(merchant.id),
                    amount=5000.0,
                    status="pending",
                    created_at=datetime.utcnow() - timedelta(days=1),
                )
            )
            db.session.commit()

            metrics = compute_autopilot_signals(window_days=30)
            self.assertEqual(int(metrics["window_days"]), 30)
            self.assertGreaterEqual(int(metrics["totals"]["order_count"]), 35)
            segments = metrics.get("segments") or []
            self.assertTrue(any(s.get("applies_to") == "declutter" for s in segments))
            target = next(
                s
                for s in segments
                if s.get("applies_to") == "declutter"
                and s.get("seller_type") == "merchant"
                and s.get("city") in ("Lagos", "all")
            )
            self.assertGreaterEqual(int(target.get("order_count") or 0), 35)
            self.assertIn("liquidity", target)

    def test_recommender_rules_liquidity_and_abuse_guard(self):
        liquidity_metrics = {
            "window_days": 30,
            "liquidity": {
                "payout_pressure": 9.2,
                "float_min_30d_minor": 100,
                "days_to_negative": 42,
            },
            "segments": [
                {
                    "applies_to": "declutter",
                    "seller_type": "merchant",
                    "city": "Lagos",
                    "order_count": 120,
                    "gmv_minor": 5_000_000,
                    "previous_order_count": 80,
                    "orders_delta_pct": 50.0,
                    "active_listings_count": 90,
                    "active_listings_delta_pct": 0.0,
                    "conversion_orders_per_active_listing": 1.33,
                    "current_policy": {"effective_rate_bps": 500},
                    "quality": {"chargeback_rate": 0.01, "dispute_count": 1},
                },
            ],
        }
        recs = generate_recommendations(liquidity_metrics)
        self.assertTrue(any((r.get("reason_code") == "LIQUIDITY_STRESS") for r in recs))

        abuse_metrics = {
            "window_days": 30,
            "liquidity": {
                "payout_pressure": 1.2,
                "float_min_30d_minor": 500000,
                "days_to_negative": None,
            },
            "segments": [
                {
                    "applies_to": "declutter",
                    "seller_type": "user",
                    "city": "Abuja",
                    "order_count": 80,
                    "gmv_minor": 2_000_000,
                    "previous_order_count": 70,
                    "orders_delta_pct": -14.0,
                    "active_listings_count": 60,
                    "active_listings_delta_pct": 0.0,
                    "conversion_orders_per_active_listing": 1.2,
                    "current_policy": {"effective_rate_bps": 500},
                    "quality": {"chargeback_rate": 0.08, "dispute_count": 7},
                },
            ],
        }
        recs = generate_recommendations(abuse_metrics)
        abuse_guarded = [
            r
            for r in recs
            if r.get("city") == "Abuja" and "QUALITY_RISK" in (r.get("risk_flags") or [])
        ]
        self.assertTrue(len(abuse_guarded) >= 1)


if __name__ == "__main__":
    unittest.main()
