from __future__ import annotations

import time
import unittest

from app import create_app
from app.extensions import db


class AuthRefreshTokensTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()
        cls.client = cls.app.test_client()

    def _unique(self) -> str:
        return str(time.time_ns())

    def _register_buyer(self) -> dict:
        suffix = self._unique()
        payload = {
            "name": f"Refresh User {suffix[-5:]}",
            "email": f"refresh-{suffix}@fliptrybe.test",
            "phone": f"080{suffix[-8:]}",
            "password": "Passw0rd!",
        }
        res = self.client.post("/api/auth/register", json=payload)
        self.assertEqual(res.status_code, 201)
        data = res.get_json(force=True) or {}
        self.assertTrue((data.get("token") or "").strip())
        self.assertTrue((data.get("refresh_token") or "").strip())
        self.assertTrue((data.get("expires_at") or "").strip())
        return data

    def test_refresh_rotation_enforced(self):
        registered = self._register_buyer()
        refresh_1 = registered.get("refresh_token")
        self.assertTrue(isinstance(refresh_1, str) and refresh_1)

        refreshed = self.client.post("/api/auth/refresh", json={"refresh_token": refresh_1})
        self.assertEqual(refreshed.status_code, 200)
        refreshed_data = refreshed.get_json(force=True) or {}
        refresh_2 = (refreshed_data.get("refresh_token") or "").strip()
        self.assertTrue(refresh_2)
        self.assertNotEqual(refresh_1, refresh_2)

        replay_old = self.client.post("/api/auth/refresh", json={"refresh_token": refresh_1})
        self.assertEqual(replay_old.status_code, 401)

    def test_logout_revokes_refresh_token(self):
        registered = self._register_buyer()
        access_token = (registered.get("token") or "").strip()
        refresh_token = (registered.get("refresh_token") or "").strip()

        logout = self.client.post(
            "/api/auth/logout",
            json={"refresh_token": refresh_token},
            headers={"Authorization": f"Bearer {access_token}"},
        )
        self.assertEqual(logout.status_code, 200)

        refreshed = self.client.post("/api/auth/refresh", json={"refresh_token": refresh_token})
        self.assertEqual(refreshed.status_code, 401)


if __name__ == "__main__":
    unittest.main()

