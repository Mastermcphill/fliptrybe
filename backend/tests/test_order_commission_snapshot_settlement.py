from __future__ import annotations

import json
import time
import unittest

from app import create_app
from app.extensions import db
from app.models import Order, User, WalletTxn
from app.segments.segment_orders_api import _ensure_order_commission_snapshot
from app.jobs.escrow_runner import (
    _credit_driver,
    _credit_seller,
    _platform_user_id,
    _settle_inspection_fee,
)
import app.utils.commission as commission_utils
from app.utils.commission import money_minor_to_major


class OrderCommissionSnapshotSettlementTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        cls.client = cls.app.test_client()
        with cls.app.app_context():
            db.create_all()
            cls._ensure_order_snapshot_columns()
            stamp = int(time.time())
            admin = User(
                name="Admin",
                email=f"snapshot-admin-{stamp}@fliptrybe.test",
                role="admin",
                phone=f"0807000{stamp % 100000:05d}",
                is_verified=True,
            )
            admin.set_password("Passw0rd!")
            merchant = User(
                name="Merchant",
                email=f"snapshot-merchant-{stamp}@fliptrybe.test",
                role="merchant",
                phone=f"0807100{stamp % 100000:05d}",
                is_verified=True,
            )
            merchant.set_password("Passw0rd!")
            driver = User(
                name="Driver",
                email=f"snapshot-driver-{stamp}@fliptrybe.test",
                role="driver",
                phone=f"0807200{stamp % 100000:05d}",
                is_verified=True,
            )
            driver.set_password("Passw0rd!")
            inspector = User(
                name="Inspector",
                email=f"snapshot-inspector-{stamp}@fliptrybe.test",
                role="inspector",
                phone=f"0807300{stamp % 100000:05d}",
                is_verified=True,
            )
            inspector.set_password("Passw0rd!")
            buyer = User(
                name="Buyer",
                email=f"snapshot-buyer-{stamp}@fliptrybe.test",
                role="buyer",
                phone=f"0807400{stamp % 100000:05d}",
                is_verified=True,
            )
            buyer.set_password("Passw0rd!")
            db.session.add_all([admin, merchant, driver, inspector, buyer])
            db.session.commit()
            cls.merchant_id = int(merchant.id)
            cls.driver_id = int(driver.id)
            cls.inspector_id = int(inspector.id)
            cls.buyer_id = int(buyer.id)

    @classmethod
    def _ensure_order_snapshot_columns(cls):
        conn = db.session.connection()
        rows = conn.exec_driver_sql("PRAGMA table_info(orders)").fetchall()
        existing = {str(row[1]) for row in rows}
        statements = {
            "commission_snapshot_version": "ALTER TABLE orders ADD COLUMN commission_snapshot_version INTEGER NOT NULL DEFAULT 1",
            "commission_snapshot_json": "ALTER TABLE orders ADD COLUMN commission_snapshot_json TEXT",
            "sale_fee_minor": "ALTER TABLE orders ADD COLUMN sale_fee_minor INTEGER NOT NULL DEFAULT 0",
            "sale_platform_minor": "ALTER TABLE orders ADD COLUMN sale_platform_minor INTEGER NOT NULL DEFAULT 0",
            "sale_seller_minor": "ALTER TABLE orders ADD COLUMN sale_seller_minor INTEGER NOT NULL DEFAULT 0",
            "sale_top_tier_incentive_minor": "ALTER TABLE orders ADD COLUMN sale_top_tier_incentive_minor INTEGER NOT NULL DEFAULT 0",
            "delivery_actor_minor": "ALTER TABLE orders ADD COLUMN delivery_actor_minor INTEGER NOT NULL DEFAULT 0",
            "delivery_platform_minor": "ALTER TABLE orders ADD COLUMN delivery_platform_minor INTEGER NOT NULL DEFAULT 0",
            "inspection_actor_minor": "ALTER TABLE orders ADD COLUMN inspection_actor_minor INTEGER NOT NULL DEFAULT 0",
            "inspection_platform_minor": "ALTER TABLE orders ADD COLUMN inspection_platform_minor INTEGER NOT NULL DEFAULT 0",
        }
        for column, sql in statements.items():
            if column in existing:
                continue
            conn.exec_driver_sql(sql)
        db.session.commit()

    def test_snapshot_is_immutable_and_drives_settlement(self):
        with self.app.app_context():
            order = Order(
                buyer_id=int(self.buyer_id),
                merchant_id=int(self.merchant_id),
                listing_id=None,
                amount=1000.00,
                total_price=1000.00,
                delivery_fee=250.00,
                inspection_fee=125.00,
                driver_id=int(self.driver_id),
                inspector_id=int(self.inspector_id),
                status="paid",
            )
            db.session.add(order)
            db.session.commit()

            snapshot_one = _ensure_order_commission_snapshot(order)
            db.session.add(order)
            db.session.commit()
            snapshot_json_one = order.commission_snapshot_json or ""

            original_listing_rate = commission_utils.RATES.get("listing_sale")
            commission_utils.RATES["listing_sale"] = 0.99
            try:
                snapshot_two = _ensure_order_commission_snapshot(order)
            finally:
                commission_utils.RATES["listing_sale"] = original_listing_rate
            self.assertEqual(snapshot_one, snapshot_two)
            self.assertEqual(snapshot_json_one, order.commission_snapshot_json or "")

            ref = f"order:{int(order.id)}"
            _credit_seller(order, None, ref, float(order.amount or 0.0))
            _credit_driver(order, ref, float(order.delivery_fee or 0.0))
            _settle_inspection_fee(order)

            snapshot = json.loads(order.commission_snapshot_json or "{}")
            sale = snapshot.get("sale", {})
            delivery = snapshot.get("delivery", {})
            inspection = snapshot.get("inspection", {})

            seller_sale = WalletTxn.query.filter_by(
                user_id=int(self.merchant_id),
                kind="order_sale",
                direction="credit",
                reference=ref,
            ).first()
            self.assertIsNotNone(seller_sale)
            self.assertAlmostEqual(
                float(seller_sale.amount or 0.0),
                money_minor_to_major(int(sale.get("seller_minor") or 0)),
                places=2,
            )

            driver_credit = WalletTxn.query.filter_by(
                user_id=int(self.driver_id),
                kind="delivery_fee",
                direction="credit",
                reference=ref,
            ).first()
            self.assertIsNotNone(driver_credit)
            self.assertAlmostEqual(
                float(driver_credit.amount or 0.0),
                money_minor_to_major(int(delivery.get("actor_minor") or 0)),
                places=2,
            )

            inspector_credit = WalletTxn.query.filter_by(
                user_id=int(self.inspector_id),
                kind="inspection_fee",
                direction="credit",
                reference=f"inspection:{int(order.id)}",
            ).first()
            self.assertIsNotNone(inspector_credit)
            self.assertAlmostEqual(
                float(inspector_credit.amount or 0.0),
                money_minor_to_major(int(inspection.get("actor_minor") or 0)),
                places=2,
            )

            platform_id = int(_platform_user_id())
            platform_sale = WalletTxn.query.filter_by(
                user_id=platform_id,
                kind="platform_fee",
                direction="credit",
                reference=ref,
            ).first()
            self.assertIsNotNone(platform_sale)
            self.assertAlmostEqual(
                float(platform_sale.amount or 0.0),
                money_minor_to_major(int(sale.get("platform_minor") or 0)),
                places=2,
            )


if __name__ == "__main__":
    unittest.main()
