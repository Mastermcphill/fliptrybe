from __future__ import annotations

import os
import time
import unittest
from datetime import datetime, timedelta

from app import create_app
from app.extensions import db
from app.models import Listing, Order, Shortlet, ShortletBooking, User


class PricingSuggestionTestCase(unittest.TestCase):
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
        user = User(
            name=f"{role}-{suffix[-4:]}",
            email=f"{role}-{suffix}@fliptrybe.test",
            phone=f"081{suffix[-8:]}",
            role=role,
            is_verified=True,
        )
        user.set_password("Passw0rd!")
        db.session.add(user)
        db.session.commit()
        return user

    def test_declutter_pricing_suggest_returns_explainable_payload(self):
        with self.app.app_context():
            merchant = self._seed_user("merchant")
            buyer = self._seed_user("buyer")
            listing = Listing(
                user_id=int(merchant.id),
                title="iPhone 12 Pro",
                description="Used iPhone with charger",
                category="phones",
                state="Lagos",
                city="Lagos",
                price=850000.0,
                base_price=850000.0,
                final_price=850000.0,
                platform_fee=0.0,
            )
            db.session.add(listing)
            db.session.flush()
            for idx in range(18):
                amount = 760000.0 + (idx * 5000.0)
                db.session.add(
                    Order(
                        buyer_id=int(buyer.id),
                        merchant_id=int(merchant.id),
                        listing_id=int(listing.id),
                        amount=float(amount),
                        total_price=float(amount),
                        delivery_fee=0.0,
                        inspection_fee=0.0,
                        sale_fee_minor=int(round(amount * 100 * 0.05)),
                        sale_seller_minor=int(round(amount * 100 * 0.95)),
                        sale_platform_minor=int(round(amount * 100 * 0.05)),
                        status="paid",
                        created_at=datetime.utcnow() - timedelta(days=idx),
                    )
                )
            db.session.commit()

        res = self.client.post(
            "/api/pricing/suggest",
            json={
                "category": "declutter",
                "city": "Lagos",
                "item_type": "iPhone 12",
                "condition": "used",
                "current_price_minor": 150000000,
            },
        )
        self.assertEqual(res.status_code, 200)
        payload = res.get_json(force=True) or {}
        self.assertTrue(payload.get("ok"))
        self.assertIn("suggested_price_minor", payload)
        self.assertIn("range_minor", payload)
        self.assertIn("explanation", payload)
        self.assertGreaterEqual(int(payload["suggested_price_minor"]), 1)
        self.assertIn(payload.get("confidence"), ("low", "medium", "high"))
        self.assertGreaterEqual(int((payload.get("benchmarks") or {}).get("sample_size") or 0), 10)

    def test_shortlet_pricing_suggest_supports_duration_hint(self):
        with self.app.app_context():
            host = self._seed_user("merchant")
            guest = self._seed_user("buyer")
            shortlet = Shortlet(
                owner_id=int(host.id),
                title="Lekki 1-bed apartment",
                description="Clean and central",
                city="Lagos",
                state="Lagos",
                nightly_price=50000.0,
                base_price=50000.0,
                final_price=50000.0,
                platform_fee=0.0,
            )
            db.session.add(shortlet)
            db.session.flush()
            for idx in range(8):
                db.session.add(
                    ShortletBooking(
                        shortlet_id=int(shortlet.id),
                        user_id=int(guest.id),
                        check_in=datetime.utcnow().date(),
                        check_out=(datetime.utcnow() + timedelta(days=2)).date(),
                        nights=2,
                        total_amount=100000.0 + (idx * 2500.0),
                        amount_minor=int((100000 + (idx * 2500)) * 100),
                        payment_status="paid",
                        status="confirmed",
                    )
                )
            db.session.commit()

        res = self.client.post(
            "/api/pricing/suggest",
            json={
                "category": "shortlet",
                "city": "Lagos",
                "item_type": "1-bed",
                "condition": "fair",
                "duration_nights": 3,
                "current_price_minor": 16000000,
            },
        )
        self.assertEqual(res.status_code, 200)
        payload = res.get_json(force=True) or {}
        self.assertTrue(payload.get("ok"))
        explanations = payload.get("explanation") or []
        self.assertTrue(any("nights" in str(x).lower() for x in explanations))


if __name__ == "__main__":
    unittest.main()
