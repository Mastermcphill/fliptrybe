from __future__ import annotations

import os
import time
import unittest

from app import create_app
from app.extensions import db
from app.models import User, WalletTxn
from app.utils.commission import compute_order_commissions_minor
from app.utils.jwt_utils import create_token


class CommissionPolicyEngineTestCase(unittest.TestCase):
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
            phone=f"090{suffix[-8:]}",
            role=role,
            is_verified=True,
        )
        row.set_password("Passw0rd!")
        db.session.add(row)
        db.session.commit()
        return row

    def test_policy_specificity_and_activation_apply_to_new_computations(self):
        with self.app.app_context():
            admin = self._seed_user("admin")
            token = create_token(int(admin.id))

        with self.app.app_context():
            # Baseline before policy activation remains default 5%
            baseline = compute_order_commissions_minor(
                sale_kind="declutter",
                sale_charge_minor=100000,
                delivery_minor=0,
                inspection_minor=0,
                is_top_tier=False,
                seller_type="merchant",
                city="Lagos",
            )
        self.assertEqual(int(baseline["sale"]["fee_minor"]), 5000)

        create_res = self.client.post(
            "/api/admin/commission/policies",
            headers={"Authorization": f"Bearer {token}"},
            json={"name": "Lagos merchant promo", "notes": "policy test"},
        )
        self.assertEqual(create_res.status_code, 201)
        policy = (create_res.get_json(force=True) or {}).get("policy") or {}
        policy_id = int(policy.get("id"))

        add_rule_res = self.client.post(
            f"/api/admin/commission/policies/{policy_id}/rules",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "applies_to": "declutter",
                "seller_type": "merchant",
                "city": "Lagos",
                "base_rate_bps": 650,
                "promo_discount_bps": 50,
                "min_fee_minor": 1000,
            },
        )
        self.assertEqual(add_rule_res.status_code, 201)
        rule = (add_rule_res.get_json(force=True) or {}).get("rule") or {}
        self.assertTrue(int(rule.get("id") or 0) > 0)

        activate_res = self.client.post(
            f"/api/admin/commission/policies/{policy_id}/activate",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(activate_res.status_code, 200)

        with self.app.app_context():
            after = compute_order_commissions_minor(
                sale_kind="declutter",
                sale_charge_minor=100000,
                delivery_minor=0,
                inspection_minor=0,
                is_top_tier=False,
                seller_type="merchant",
                city="Lagos",
            )
        self.assertEqual(int(after["sale"]["fee_minor"]), 6000)
        self.assertEqual(int((after.get("policy") or {}).get("effective_rate_bps") or 0), 600)
        self.assertEqual(int((after.get("policy") or {}).get("rule_id") or 0), int(rule["id"]))

    def test_preview_is_read_only_for_ledger(self):
        with self.app.app_context():
            admin = self._seed_user("admin")
            token = create_token(int(admin.id))
            before = WalletTxn.query.count()

        res = self.client.get(
            "/api/admin/commission/preview?applies_to=declutter&seller_type=user&city=Lagos&amount_minor=200000",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(res.status_code, 200)
        payload = res.get_json(force=True) or {}
        self.assertTrue(payload.get("ok"))
        self.assertIn("commission_fee_minor", payload)

        with self.app.app_context():
            after = WalletTxn.query.count()
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
