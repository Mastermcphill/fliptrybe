from __future__ import annotations

import os
import time
import unittest
from datetime import datetime, timedelta

from app import create_app
from app.extensions import db
from app.models import Order, PayoutRequest, User, Wallet
from app.services.simulation.liquidity_simulator import (
    get_liquidity_baseline,
    run_liquidity_simulation,
)
from app.utils.jwt_utils import create_token


class LiquiditySimulationTestCase(unittest.TestCase):
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
            name=f"{role}-{suffix[-4:]}",
            email=f"{role}-{suffix}@fliptrybe.test",
            phone=f"081{suffix[-8:]}",
            role=role,
            is_verified=True,
        )
        row.set_password("Passw0rd!")
        db.session.add(row)
        db.session.commit()
        return row

    def test_baseline_and_simulation_endpoints_are_deterministic(self):
        with self.app.app_context():
            admin = self._seed_user("admin")
            merchant = self._seed_user("merchant")
            buyer = self._seed_user("buyer")

            wallet = Wallet(user_id=int(admin.id), balance=250000.0, reserved_balance=0.0, currency="NGN")
            db.session.add(wallet)

            for idx in range(12):
                db.session.add(
                    Order(
                        buyer_id=int(buyer.id),
                        merchant_id=int(merchant.id),
                        amount=50000.0 + idx * 1000,
                        total_price=50000.0 + idx * 1000,
                        delivery_fee=2000.0,
                        inspection_fee=500.0,
                        status="paid",
                        sale_platform_minor=250000,
                        sale_seller_minor=4750000,
                        delivery_platform_minor=20000,
                        inspection_platform_minor=5000,
                        created_at=datetime.utcnow() - timedelta(days=idx),
                    )
                )
            db.session.add(
                PayoutRequest(
                    user_id=int(merchant.id),
                    amount=80000.0,
                    fee_amount=0.0,
                    net_amount=80000.0,
                    status="pending",
                    created_at=datetime.utcnow() - timedelta(days=5),
                )
            )
            db.session.commit()
            token = create_token(int(admin.id))

        with self.app.app_context():
            baseline = get_liquidity_baseline()
        self.assertTrue(baseline["ok"])
        self.assertGreaterEqual(int(baseline["avg_daily_gmv_minor"]), 1)

        payload = {
            "time_horizon_days": 45,
            "assumed_daily_gmv_minor": int(baseline["avg_daily_gmv_minor"]),
            "assumed_order_count_daily": float(baseline["avg_daily_orders"]),
            "withdrawal_rate_pct": float(baseline["withdrawal_ratio"]) * 100.0,
            "payout_delay_days": 4,
            "chargeback_rate_pct": 1.5,
            "operating_cost_daily_minor": 400000,
            "commission_bps": 500,
            "scenario": "base",
        }
        with self.app.app_context():
            first = run_liquidity_simulation(**payload)
            second = run_liquidity_simulation(**payload)
        self.assertEqual(first["projected_commission_revenue_minor"], second["projected_commission_revenue_minor"])
        self.assertEqual(first["min_cash_balance_minor"], second["min_cash_balance_minor"])

        baseline_res = self.client.get(
            "/api/admin/simulation/baseline",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(baseline_res.status_code, 200)
        baseline_payload = baseline_res.get_json(force=True) or {}
        self.assertTrue(baseline_payload.get("ok"))
        self.assertIn("avg_daily_gmv_minor", baseline_payload)

        sim_res = self.client.post(
            "/api/admin/simulation/liquidity",
            headers={"Authorization": f"Bearer {token}"},
            json=payload,
        )
        self.assertEqual(sim_res.status_code, 200)
        sim_payload = sim_res.get_json(force=True) or {}
        self.assertTrue(sim_payload.get("ok"))
        self.assertIn("series", sim_payload)
        self.assertEqual(len(sim_payload.get("series") or []), 45)


if __name__ == "__main__":
    unittest.main()
