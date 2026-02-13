from __future__ import annotations

import time
import unittest

from app import create_app
from app.extensions import db
from app.models import MoneyBoxAccount, User
from app.utils.jwt_utils import create_token


class MoneyboxAutosaveSettingsTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()
            stamp = int(time.time())
            merchant = User(
                name="Autosave Merchant",
                email=f"autosave-merchant-{stamp}@fliptrybe.test",
                role="merchant",
                phone=f"0801000{stamp % 100000:05d}",
                is_verified=True,
            )
            merchant.set_password("Passw0rd!")
            buyer = User(
                name="Autosave Buyer",
                email=f"autosave-buyer-{stamp}@fliptrybe.test",
                role="buyer",
                phone=f"0802000{stamp % 100000:05d}",
                is_verified=True,
            )
            buyer.set_password("Passw0rd!")
            db.session.add(merchant)
            db.session.add(buyer)
            db.session.commit()
            cls.merchant_id = int(merchant.id)
            cls.buyer_id = int(buyer.id)
        cls.client = cls.app.test_client()

    def _auth_headers(self, user_id: int) -> dict[str, str]:
        token = create_token(user_id)
        return {"Authorization": f"Bearer {token}"}

    def test_get_autosave_settings_for_eligible_role(self):
        res = self.client.get(
            "/api/moneybox/autosave/settings",
            headers=self._auth_headers(self.merchant_id),
        )
        self.assertEqual(res.status_code, 200)
        body = res.get_json(force=True)
        self.assertTrue(body.get("ok"))
        self.assertTrue(body.get("role_eligible"))
        self.assertIn("autosave_enabled", body)
        self.assertIn("autosave_percent", body)
        self.assertEqual(body.get("min_percent"), 1)
        self.assertEqual(body.get("max_percent"), 30)

    def test_post_autosave_settings_validation(self):
        bad = self.client.post(
            "/api/moneybox/autosave/settings",
            headers=self._auth_headers(self.merchant_id),
            json={"autosave_enabled": True, "autosave_percent": 50},
        )
        self.assertEqual(bad.status_code, 400)
        bad_body = bad.get_json(force=True)
        self.assertFalse(bad_body.get("ok"))

        good = self.client.post(
            "/api/moneybox/autosave/settings",
            headers=self._auth_headers(self.merchant_id),
            json={"autosave_enabled": True, "autosave_percent": 12},
        )
        self.assertEqual(good.status_code, 200)
        good_body = good.get_json(force=True)
        self.assertTrue(good_body.get("ok"))
        self.assertTrue(good_body.get("autosave_enabled"))
        self.assertEqual(int(good_body.get("autosave_percent") or 0), 12)

        with self.app.app_context():
            acct = MoneyBoxAccount.query.filter_by(user_id=int(self.merchant_id)).first()
            self.assertIsNotNone(acct)
            self.assertTrue(bool(acct.autosave_enabled))
            self.assertEqual(int(round(float(acct.autosave_percent or 0))), 12)

    def test_post_autosave_settings_for_non_eligible_role(self):
        res = self.client.post(
            "/api/moneybox/autosave/settings",
            headers=self._auth_headers(self.buyer_id),
            json={"autosave_enabled": True, "autosave_percent": 10},
        )
        self.assertEqual(res.status_code, 403)
        body = res.get_json(force=True)
        self.assertFalse(body.get("ok", False))


if __name__ == "__main__":
    unittest.main()
