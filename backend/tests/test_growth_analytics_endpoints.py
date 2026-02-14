from __future__ import annotations

import os
import time
import unittest
from datetime import datetime, timedelta

from app import create_app
from app.extensions import db
from app.models import (
    Listing,
    Order,
    PayoutRequest,
    Shortlet,
    ShortletBooking,
    User,
    Wallet,
    WalletTxn,
)
from app.utils.jwt_utils import create_token


class GrowthAnalyticsEndpointsTestCase(unittest.TestCase):
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
            name=f"{role.title()} {suffix[-4:]}",
            email=f"{role}-{suffix}@fliptrybe.test",
            phone=f"081{suffix[-8:]}",
            role=role,
            is_verified=True,
        )
        user.set_password("Passw0rd!")
        db.session.add(user)
        db.session.commit()
        return user

    def test_admin_growth_and_economics_contracts(self):
        with self.app.app_context():
            admin = self._seed_user("admin")
            merchant = self._seed_user("merchant")
            buyer = self._seed_user("buyer")

            listing = Listing(
                user_id=int(merchant.id),
                title="Growth Listing",
                description="growth seed",
                category="electronics",
                price=30000.0,
                base_price=30000.0,
                platform_fee=0.0,
                final_price=30000.0,
                state="Lagos",
                city="Ikeja",
                image_path="",
                date_posted=datetime.utcnow(),
                views_count=120,
            )
            db.session.add(listing)
            db.session.commit()

            order = Order(
                buyer_id=int(buyer.id),
                merchant_id=int(merchant.id),
                listing_id=int(listing.id),
                amount=30000.0,
                total_price=30000.0,
                delivery_fee=1500.0,
                inspection_fee=500.0,
                status="paid",
                sale_platform_minor=150000,
                sale_seller_minor=2850000,
                sale_fee_minor=150000,
                delivery_platform_minor=15000,
                inspection_platform_minor=5000,
                payment_reference=f"growth-{int(time.time())}",
                created_at=datetime.utcnow() - timedelta(days=10),
                updated_at=datetime.utcnow(),
            )
            db.session.add(order)

            shortlet = Shortlet(
                owner_id=int(merchant.id),
                title="Seed Shortlet",
                description="seed",
                state="Lagos",
                city="Lekki",
                nightly_price=50000.0,
                base_price=50000.0,
                platform_fee=0.0,
                final_price=50000.0,
            )
            db.session.add(shortlet)
            db.session.commit()

            booking = ShortletBooking(
                shortlet_id=int(shortlet.id),
                user_id=int(buyer.id),
                payment_status="paid",
                status="confirmed",
                check_in=datetime.utcnow().date(),
                check_out=(datetime.utcnow() + timedelta(days=2)).date(),
                nights=2,
                total_amount=100000.0,
                created_at=datetime.utcnow() - timedelta(days=5),
            )
            db.session.add(booking)

            platform_wallet = Wallet(
                user_id=int(admin.id),
                balance=4000.0,
                reserved_balance=0.0,
                currency="NGN",
            )
            db.session.add(platform_wallet)
            db.session.commit()
            db.session.add(
                WalletTxn(
                    wallet_id=int(platform_wallet.id),
                    user_id=int(admin.id),
                    direction="credit",
                    amount=1700.0,
                    kind="platform_fee",
                    reference="order:seed",
                    note="seed",
                )
            )
            db.session.add(
                PayoutRequest(
                    user_id=int(merchant.id),
                    amount=12000.0,
                    fee_amount=100.0,
                    net_amount=11900.0,
                    status="pending",
                )
            )
            db.session.commit()

            admin_token = create_token(int(admin.id))

        overview_res = self.client.get(
            "/api/admin/analytics/overview",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        self.assertEqual(overview_res.status_code, 200)
        overview = overview_res.get_json(force=True) or {}
        self.assertIn("total_gmv_minor", overview)
        self.assertIn("total_commission_minor", overview)
        self.assertGreater(int(overview.get("total_gmv_minor") or 0), 0)

        breakdown_res = self.client.get(
            "/api/admin/analytics/revenue-breakdown",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        self.assertEqual(breakdown_res.status_code, 200)
        breakdown = breakdown_res.get_json(force=True) or {}
        self.assertIn("declutter_gmv", breakdown)
        self.assertIn("shortlet_gmv", breakdown)
        self.assertIn("commissions_by_type", breakdown)

        projection_res = self.client.get(
            "/api/admin/analytics/projection?months=6",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        self.assertEqual(projection_res.status_code, 200)
        projection = projection_res.get_json(force=True) or {}
        self.assertEqual(len(projection.get("projections") or []), 6)
        self.assertIn("assumptions", projection)

        csv_res = self.client.get(
            "/api/admin/analytics/export-csv",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        self.assertEqual(csv_res.status_code, 200)
        self.assertIn("text/csv", csv_res.headers.get("Content-Type", ""))

        economics_res = self.client.get(
            "/api/admin/economics/health",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        self.assertEqual(economics_res.status_code, 200)
        economics = economics_res.get_json(force=True) or {}
        for key in (
            "total_platform_wallet_balance_minor",
            "pending_withdrawals_count",
            "commission_float_minor",
            "revenue_last_30_days_minor",
        ):
            self.assertIn(key, economics)

    def test_buyer_and_merchant_analytics_endpoints(self):
        with self.app.app_context():
            merchant = self._seed_user("merchant")
            buyer = self._seed_user("buyer")
            listing = Listing(
                user_id=int(merchant.id),
                title="Analytics Listing",
                description="seed",
                category="electronics",
                price=10000.0,
                base_price=10000.0,
                platform_fee=0.0,
                final_price=10000.0,
                state="Lagos",
                city="Ikeja",
                image_path="",
                date_posted=datetime.utcnow(),
                views_count=25,
            )
            db.session.add(listing)
            db.session.commit()
            order = Order(
                buyer_id=int(buyer.id),
                merchant_id=int(merchant.id),
                listing_id=int(listing.id),
                amount=10000.0,
                total_price=10000.0,
                status="paid",
                sale_fee_minor=50000,
                sale_seller_minor=950000,
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow(),
            )
            db.session.add(order)
            db.session.commit()
            merchant_token = create_token(int(merchant.id))
            buyer_token = create_token(int(buyer.id))

        merchant_res = self.client.get(
            "/api/merchant/analytics",
            headers={"Authorization": f"Bearer {merchant_token}"},
        )
        self.assertEqual(merchant_res.status_code, 200)
        merchant_payload = merchant_res.get_json(force=True) or {}
        self.assertIn("total_sales", merchant_payload)
        self.assertIn("commission_paid_minor", merchant_payload)
        self.assertIn("net_earnings_minor", merchant_payload)
        self.assertIn("conversion_rate", merchant_payload)

        buyer_res = self.client.get(
            "/api/buyer/analytics",
            headers={"Authorization": f"Bearer {buyer_token}"},
        )
        self.assertEqual(buyer_res.status_code, 200)
        buyer_payload = buyer_res.get_json(force=True) or {}
        self.assertIn("total_purchases", buyer_payload)
        self.assertIn("total_spent_minor", buyer_payload)
        self.assertIn("saved_listings_count", buyer_payload)


if __name__ == "__main__":
    unittest.main()
