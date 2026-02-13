from __future__ import annotations

import time
import unittest

from app import create_app
from app.extensions import db


class AuthPayloadStabilityTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()
        cls.client = cls.app.test_client()

    def _unique(self) -> str:
        return str(time.time_ns())

    def test_login_and_me_include_stable_role_metadata_defaults(self):
        suffix = self._unique()
        register_payload = {
            "name": "Stable Payload Buyer",
            "email": f"stable-buyer-{suffix}@fliptrybe.test",
            "phone": f"081{suffix[-8:]}",
            "password": "Passw0rd!",
            "role": "buyer",
        }
        register = self.client.post("/api/auth/register", json=register_payload)
        self.assertEqual(register.status_code, 201)
        token = (register.get_json(force=True) or {}).get("token")
        self.assertTrue(isinstance(token, str) and token)

        login = self.client.post(
            "/api/auth/login",
            json={"email": register_payload["email"], "password": register_payload["password"]},
        )
        self.assertEqual(login.status_code, 200)
        login_user = (login.get_json(force=True) or {}).get("user") or {}

        self.assertEqual((login_user.get("role") or "").lower(), "buyer")
        self.assertEqual((login_user.get("role_status") or "").lower(), "approved")
        self.assertEqual((login_user.get("requested_role") or "").lower(), "buyer")
        self.assertEqual((login_user.get("role_request_status") or "").lower(), "none")

        me = self.client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
        self.assertEqual(me.status_code, 200)
        me_user = me.get_json(force=True) or {}
        self.assertEqual((me_user.get("role") or "").lower(), "buyer")
        self.assertEqual((me_user.get("role_status") or "").lower(), "approved")
        self.assertEqual((me_user.get("requested_role") or "").lower(), "buyer")
        self.assertEqual((me_user.get("role_request_status") or "").lower(), "none")


if __name__ == "__main__":
    unittest.main()
