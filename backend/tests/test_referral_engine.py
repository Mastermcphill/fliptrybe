from __future__ import annotations

import os
import time
import unittest
from datetime import datetime

from app import create_app
from app.extensions import db
from app.models import Listing, Order, Referral, User, WalletTxn
from app.services.referral_service import (
    apply_referral_code,
    ensure_user_referral_code,
    maybe_complete_referral_on_success,
)
from app.utils.jwt_utils import create_token


class ReferralEngineTestCase(unittest.TestCase):
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

    def _seed_user(self, role: str = "buyer") -> User:
        suffix = str(time.time_ns())
        user = User(
            name=f"{role.title()} {suffix[-4:]}",
            email=f"{role}-{suffix}@fliptrybe.test",
            phone=f"080{suffix[-8:]}",
            role=role,
            is_verified=True,
        )
        user.set_password("Passw0rd!")
        db.session.add(user)
        db.session.commit()
        ensure_user_referral_code(user)
        return user

    def test_referral_apply_and_complete_exactly_once(self):
        with self.app.app_context():
            referrer = self._seed_user(role="buyer")
            merchant = self._seed_user(role="merchant")
            referred = self._seed_user(role="buyer")
            ref_code = ensure_user_referral_code(referrer)

            apply_res = apply_referral_code(user=referred, code=ref_code)
            self.assertTrue(apply_res.get("ok"))
            row = Referral.query.filter_by(referred_user_id=int(referred.id)).first()
            self.assertIsNotNone(row)
            self.assertEqual((row.status or "").lower(), "pending")

            listing = Listing(
                user_id=int(merchant.id),
                title="Referral Order Listing",
                description="seed",
                category="electronics",
                price=15000.0,
                base_price=15000.0,
                platform_fee=0.0,
                final_price=15000.0,
                state="Lagos",
                city="Ikeja",
                image_path="",
                date_posted=datetime.utcnow(),
            )
            db.session.add(listing)
            db.session.commit()

            order = Order(
                buyer_id=int(referred.id),
                merchant_id=int(merchant.id),
                listing_id=int(listing.id),
                amount=15000.0,
                total_price=15000.0,
                delivery_fee=0.0,
                inspection_fee=0.0,
                status="paid",
                payment_reference=f"ref-test-{int(time.time())}",
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow(),
            )
            db.session.add(order)
            db.session.commit()

            first = maybe_complete_referral_on_success(
                referred_user_id=int(referred.id),
                source_type="order",
                source_id=int(order.id),
            )
            self.assertTrue(first.get("ok"))
            self.assertTrue(first.get("completed"))

            second = maybe_complete_referral_on_success(
                referred_user_id=int(referred.id),
                source_type="order",
                source_id=int(order.id),
            )
            self.assertTrue(second.get("ok"))
            self.assertFalse(second.get("completed"))

            txns = WalletTxn.query.filter(
                WalletTxn.user_id == int(referrer.id),
                WalletTxn.kind == "referral_reward",
            ).all()
            self.assertEqual(len(txns), 1)
            row = Referral.query.filter_by(referred_user_id=int(referred.id)).first()
            self.assertEqual((row.status or "").lower(), "completed")

    def test_referral_endpoints(self):
        with self.app.app_context():
            referrer = self._seed_user(role="buyer")
            referred = self._seed_user(role="buyer")
            token = create_token(int(referred.id))
            referrer_code = ensure_user_referral_code(referrer)

        code_res = self.client.get(
            "/api/referral/code",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(code_res.status_code, 200)
        self.assertTrue((code_res.get_json(force=True) or {}).get("referral_code"))

        apply_res = self.client.post(
            "/api/referral/apply",
            headers={"Authorization": f"Bearer {token}"},
            json={"referral_code": referrer_code},
        )
        self.assertEqual(apply_res.status_code, 200)
        self.assertTrue((apply_res.get_json(force=True) or {}).get("ok"))

        stats_res = self.client.get(
            "/api/referral/stats",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(stats_res.status_code, 200)
        stats = stats_res.get_json(force=True) or {}
        self.assertIn("joined", stats)
        self.assertIn("earned_minor", stats)


if __name__ == "__main__":
    unittest.main()
