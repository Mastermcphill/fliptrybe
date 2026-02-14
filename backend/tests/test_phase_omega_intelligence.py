from __future__ import annotations

import os
import time
import unittest
from datetime import datetime, timedelta

from app import create_app
from app.extensions import db
from app.models import FraudFlag, Listing, Order, Referral, User, WalletTxn
from app.services.elasticity import compute_segment_elasticity
from app.services.fraud import compute_user_fraud_score
from app.services.simulation import simulate_cross_market_balance, simulate_geo_expansion
from app.utils.jwt_utils import create_token
from app.utils.wallets import get_or_create_wallet


class PhaseOmegaIntelligenceTestCase(unittest.TestCase):
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

    def _seed_user(self, role: str, *, verified: bool = True) -> User:
        suffix = str(time.time_ns())
        row = User(
            name=f"{role}-{suffix[-4:]}",
            email=f"{role}-{suffix}@fliptrybe.test",
            phone=f"080{suffix[-8:]}",
            role=role,
            is_verified=verified,
            referred_by=None,
        )
        row.set_password("Passw0rd!")
        db.session.add(row)
        db.session.commit()
        return row

    def _seed_declutter_history(self):
        merchant = self._seed_user("merchant")
        buyer = self._seed_user("buyer")
        base_prices = [120000.0, 145000.0, 160000.0, 185000.0, 210000.0]
        listing_ids = []
        for idx, price in enumerate(base_prices):
            listing = Listing(
                user_id=int(merchant.id),
                title=f"Phone {idx}",
                description="Test",
                category="declutter",
                city="Lagos",
                state="Lagos",
                price=price,
                final_price=price,
                is_active=True,
                created_at=datetime.utcnow() - timedelta(days=10),
            )
            db.session.add(listing)
            db.session.flush()
            listing_ids.append(int(listing.id))
        for idx, listing_id in enumerate(listing_ids):
            for _ in range(8):
                total_price = base_prices[idx]
                db.session.add(
                    Order(
                        buyer_id=int(buyer.id),
                        merchant_id=int(merchant.id),
                        listing_id=int(listing_id),
                        amount=total_price,
                        total_price=total_price,
                        sale_fee_minor=int(round(total_price * 5)),
                        sale_platform_minor=int(round(total_price * 5)),
                        status="paid",
                        created_at=datetime.utcnow() - timedelta(days=4),
                        updated_at=datetime.utcnow() - timedelta(days=4),
                    )
                )
        db.session.commit()

    def test_elasticity_calculation_is_deterministic(self):
        with self.app.app_context():
            self._seed_declutter_history()
            first = compute_segment_elasticity(
                category="declutter",
                city="Lagos",
                seller_type="merchant",
                window_days=90,
                persist_snapshot=True,
            )
            second = compute_segment_elasticity(
                category="declutter",
                city="Lagos",
                seller_type="merchant",
                window_days=90,
                persist_snapshot=True,
            )
            self.assertTrue(first.get("ok", True))
            self.assertEqual(first.get("elasticity_coefficient"), second.get("elasticity_coefficient"))
            self.assertEqual(first.get("hash_key"), second.get("hash_key"))
            self.assertGreaterEqual(int(first.get("sample_size") or 0), 1)

    def test_fraud_score_is_deterministic_for_self_referral(self):
        with self.app.app_context():
            user = self._seed_user("buyer")
            user.referred_by = int(user.id)
            db.session.add(user)
            db.session.flush()
            db.session.add(
                Referral(
                    referrer_user_id=int(user.id),
                    referred_user_id=int(user.id),
                    referral_code="SELFTEST",
                    status="pending",
                    reward_amount_minor=0,
                )
            )
            db.session.commit()

            first = compute_user_fraud_score(int(user.id))
            second = compute_user_fraud_score(int(user.id))
            self.assertEqual(int(first.get("score") or 0), int(second.get("score") or 0))
            reasons = first.get("reasons") or []
            codes = {(r.get("code") or "") for r in reasons if isinstance(r, dict)}
            self.assertIn("SELF_REFERRAL_PATTERN", codes)
            self.assertGreaterEqual(int(first.get("score") or 0), 80)

    def test_freeze_flag_blocks_withdrawal_request(self):
        with self.app.app_context():
            user = self._seed_user("buyer")
            wallet = get_or_create_wallet(int(user.id))
            wallet.balance = 50000.0
            db.session.add(wallet)
            db.session.add(
                FraudFlag(
                    user_id=int(user.id),
                    score=92,
                    reasons_json='{"items":[{"code":"TEST","weight":92}]}',
                    status="open",
                    created_at=datetime.utcnow(),
                    updated_at=datetime.utcnow(),
                )
            )
            db.session.commit()
            token = create_token(int(user.id))

        res = self.client.post(
            "/api/wallet/payouts",
            headers={"Authorization": f"Bearer {token}"},
            json={"amount": 1000, "bank_name": "Test", "account_number": "1234567890", "account_name": "T User"},
        )
        self.assertEqual(res.status_code, 403)
        payload = res.get_json(force=True) or {}
        self.assertEqual(payload.get("code"), "FRAUD_WITHDRAWAL_BLOCKED")

    def test_cross_market_simulation_read_only(self):
        with self.app.app_context():
            before_txn_count = WalletTxn.query.count()
            result = simulate_cross_market_balance(
                time_horizon_days=60,
                commission_shift_city="Lagos",
                commission_shift_bps=50,
                promo_city="Abuja",
                promo_discount_bps=30,
                payout_delay_adjustment_days=2,
            )
            after_txn_count = WalletTxn.query.count()
        self.assertTrue(result.get("ok"))
        self.assertEqual(before_txn_count, after_txn_count)

    def test_expansion_simulation_is_deterministic(self):
        with self.app.app_context():
            first = simulate_geo_expansion(
                target_city="Abeokuta",
                assumed_listings=50,
                assumed_daily_gmv_minor=25000000,
                average_order_value_minor=750000,
                marketing_budget_minor=150000000,
                estimated_commission_bps=500,
                operating_cost_daily_minor=800000,
            )
            second = simulate_geo_expansion(
                target_city="Abeokuta",
                assumed_listings=50,
                assumed_daily_gmv_minor=25000000,
                average_order_value_minor=750000,
                marketing_budget_minor=150000000,
                estimated_commission_bps=500,
                operating_cost_daily_minor=800000,
            )
        self.assertTrue(first.get("ok"))
        self.assertEqual(first.get("projected_6_month_gmv_minor"), second.get("projected_6_month_gmv_minor"))
        self.assertEqual(first.get("projected_commission_revenue_minor"), second.get("projected_commission_revenue_minor"))
        self.assertEqual(first.get("roi_projection_pct"), second.get("roi_projection_pct"))

    def test_admin_omega_endpoints_contract(self):
        with self.app.app_context():
            admin = self._seed_user("admin")
            self._seed_declutter_history()
            flag_user = self._seed_user("buyer")
            flag = FraudFlag(
                user_id=int(flag_user.id),
                score=75,
                reasons_json='{"items":[{"code":"TEST","weight":75}]}',
                status="open",
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow(),
            )
            db.session.add(flag)
            db.session.commit()
            flag_id = int(flag.id)
            token = create_token(int(admin.id))

        headers = {"Authorization": f"Bearer {token}"}
        elasticity_res = self.client.get(
            "/api/admin/elasticity/segment?category=declutter&city=Lagos&seller_type=merchant",
            headers=headers,
        )
        self.assertEqual(elasticity_res.status_code, 200)
        elasticity_payload = elasticity_res.get_json(force=True) or {}
        self.assertIn("elasticity_coefficient", elasticity_payload)

        review_res = self.client.post(
            f"/api/admin/fraud/{flag_id}/review",
            headers=headers,
            json={"status": "reviewed", "note": "checked"},
        )
        self.assertEqual(review_res.status_code, 200)
        review_payload = review_res.get_json(force=True) or {}
        self.assertTrue(review_payload.get("ok"))

        liquidity_res = self.client.post(
            "/api/admin/liquidity/cross-market-simulate",
            headers=headers,
            json={"time_horizon_days": 45},
        )
        self.assertEqual(liquidity_res.status_code, 200)
        self.assertTrue((liquidity_res.get_json(force=True) or {}).get("ok"))

        expansion_res = self.client.post(
            "/api/admin/expansion/simulate",
            headers=headers,
            json={
                "target_city": "Asaba",
                "assumed_listings": 40,
                "assumed_daily_gmv_minor": 15000000,
                "average_order_value_minor": 500000,
                "marketing_budget_minor": 100000000,
                "estimated_commission_bps": 500,
                "operating_cost_daily_minor": 500000,
            },
        )
        self.assertEqual(expansion_res.status_code, 200)
        expansion_payload = expansion_res.get_json(force=True) or {}
        self.assertIn("projected_6_month_gmv_minor", expansion_payload)


if __name__ == "__main__":
    unittest.main()
