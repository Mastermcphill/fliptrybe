from __future__ import annotations

import time
import unittest
from datetime import datetime

from app import create_app
from app.extensions import db
from app.jobs.escrow_runner import run_escrow_automation
from app.models import EscrowUnlock, Order, User, WalletTxn
from app.segments.segment_orders_api import _mark_paid


class ReleaseMoneyFlowSmokeTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()
        cls.client = cls.app.test_client()

    def _seed_users(self) -> dict[str, int]:
        suffix = int(time.time_ns())
        merchant = User(
            name="Smoke Merchant",
            email=f"smoke-merchant-{suffix}@fliptrybe.test",
            role="merchant",
            phone=f"0808{suffix % 10000000:07d}",
            is_verified=True,
        )
        merchant.set_password("Passw0rd!")

        buyer = User(
            name="Smoke Buyer",
            email=f"smoke-buyer-{suffix}@fliptrybe.test",
            role="buyer",
            phone=f"0807{suffix % 10000000:07d}",
            is_verified=True,
        )
        buyer.set_password("Passw0rd!")

        driver = User(
            name="Smoke Driver",
            email=f"smoke-driver-{suffix}@fliptrybe.test",
            role="driver",
            phone=f"0806{suffix % 10000000:07d}",
            is_verified=True,
        )
        driver.set_password("Passw0rd!")

        inspector = User(
            name="Smoke Inspector",
            email=f"smoke-inspector-{suffix}@fliptrybe.test",
            role="inspector",
            phone=f"0805{suffix % 10000000:07d}",
            is_verified=True,
        )
        inspector.set_password("Passw0rd!")

        platform_admin = User.query.filter_by(role="admin").order_by(User.id.asc()).first()
        if platform_admin is None:
            platform_admin = User(
                name="Platform Admin",
                email=f"smoke-admin-{suffix}@fliptrybe.test",
                role="admin",
                phone=f"0804{suffix % 10000000:07d}",
                is_verified=True,
            )
            platform_admin.set_password("Passw0rd!")
            db.session.add(platform_admin)

        db.session.add_all([merchant, buyer, driver, inspector])
        db.session.commit()

        return {
            "merchant_id": int(merchant.id),
            "buyer_id": int(buyer.id),
            "driver_id": int(driver.id),
            "inspector_id": int(inspector.id),
            "admin_id": int(platform_admin.id),
        }

    def test_order_paid_to_release_and_wallet_credits_are_idempotent(self):
        with self.app.app_context():
            ids = self._seed_users()
            order = Order(
                buyer_id=int(ids["buyer_id"]),
                merchant_id=int(ids["merchant_id"]),
                listing_id=None,
                amount=1500.0,
                total_price=1500.0,
                delivery_fee=300.0,
                inspection_fee=200.0,
                driver_id=int(ids["driver_id"]),
                inspector_id=int(ids["inspector_id"]),
                inspection_required=True,
                release_condition="INSPECTION_PASS",
                status="created",
            )
            db.session.add(order)
            db.session.commit()

            _mark_paid(order, reference=f"SMOKE-ORDER-{int(order.id)}", actor_id=int(ids["buyer_id"]))
            order.inspection_outcome = "PASS"
            db.session.add(
                EscrowUnlock(
                    order_id=int(order.id),
                    step="inspection_inspector",
                    unlocked_at=datetime.utcnow(),
                    qr_required=False,
                )
            )
            db.session.commit()

            first = run_escrow_automation(limit=50)
            self.assertTrue(first.get("ok"))
            db.session.refresh(order)
            self.assertEqual((order.escrow_status or "").upper(), "RELEASED")
            self.assertTrue((order.commission_snapshot_json or "").strip())

            order_ref = f"order:{int(order.id)}"
            inspection_ref = f"inspection:{int(order.id)}"

            merchant_sale = WalletTxn.query.filter_by(
                user_id=int(ids["merchant_id"]),
                direction="credit",
                kind="order_sale",
                reference=order_ref,
            ).count()
            driver_fee = WalletTxn.query.filter_by(
                user_id=int(ids["driver_id"]),
                direction="credit",
                kind="delivery_fee",
                reference=order_ref,
            ).count()
            inspector_fee = WalletTxn.query.filter_by(
                user_id=int(ids["inspector_id"]),
                direction="credit",
                kind="inspection_fee",
                reference=inspection_ref,
            ).count()

            self.assertEqual(merchant_sale, 1)
            self.assertEqual(driver_fee, 1)
            self.assertEqual(inspector_fee, 1)

            second = run_escrow_automation(limit=50)
            self.assertTrue(second.get("ok"))

            merchant_sale_after = WalletTxn.query.filter_by(
                user_id=int(ids["merchant_id"]),
                direction="credit",
                kind="order_sale",
                reference=order_ref,
            ).count()
            driver_fee_after = WalletTxn.query.filter_by(
                user_id=int(ids["driver_id"]),
                direction="credit",
                kind="delivery_fee",
                reference=order_ref,
            ).count()
            inspector_fee_after = WalletTxn.query.filter_by(
                user_id=int(ids["inspector_id"]),
                direction="credit",
                kind="inspection_fee",
                reference=inspection_ref,
            ).count()

            self.assertEqual(merchant_sale_after, 1)
            self.assertEqual(driver_fee_after, 1)
            self.assertEqual(inspector_fee_after, 1)

    def test_legacy_paid_order_missing_snapshot_is_backfilled_once(self):
        with self.app.app_context():
            ids = self._seed_users()
            legacy_order = Order(
                buyer_id=int(ids["buyer_id"]),
                merchant_id=int(ids["merchant_id"]),
                listing_id=None,
                amount=1000.0,
                total_price=1000.0,
                delivery_fee=150.0,
                inspection_fee=100.0,
                driver_id=int(ids["driver_id"]),
                inspector_id=int(ids["inspector_id"]),
                inspection_required=True,
                release_condition="INSPECTION_PASS",
                status="paid",
                escrow_status="HELD",
                commission_snapshot_json=None,
                sale_fee_minor=0,
                sale_platform_minor=0,
                sale_seller_minor=0,
                sale_top_tier_incentive_minor=0,
                delivery_actor_minor=0,
                delivery_platform_minor=0,
                inspection_actor_minor=0,
                inspection_platform_minor=0,
            )
            db.session.add(legacy_order)
            db.session.flush()
            db.session.add(
                EscrowUnlock(
                    order_id=int(legacy_order.id),
                    step="inspection_inspector",
                    unlocked_at=datetime.utcnow(),
                    qr_required=False,
                )
            )
            legacy_order.inspection_outcome = "PASS"
            db.session.commit()

            result = run_escrow_automation(limit=50)
            self.assertTrue(result.get("ok"))
            db.session.refresh(legacy_order)
            self.assertEqual((legacy_order.escrow_status or "").upper(), "RELEASED")
            self.assertTrue((legacy_order.commission_snapshot_json or "").strip())
            self.assertGreater(int(legacy_order.sale_fee_minor or 0), 0)


if __name__ == "__main__":
    unittest.main()
