from __future__ import annotations

import os
import unittest

from app import create_app
from app.extensions import db
from app.models import User


class PhoneOtpAuthTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._prev_db_uri = os.getenv("SQLALCHEMY_DATABASE_URI")
        cls._prev_db_url = os.getenv("DATABASE_URL")
        cls._prev_env = os.getenv("FLIPTRYBE_ENV")
        cls._prev_termii = os.getenv("TERMII_API_KEY")

        db_uri = "sqlite:///:memory:"
        os.environ["SQLALCHEMY_DATABASE_URI"] = db_uri
        os.environ["DATABASE_URL"] = db_uri
        os.environ["FLIPTRYBE_ENV"] = "dev"
        os.environ.pop("TERMII_API_KEY", None)

        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()
            user = User(
                name="OTP User",
                email="otp-user@fliptrybe.dev",
                phone="+2348100002000",
                role="buyer",
                is_verified=False,
            )
            user.set_password("password123")
            db.session.add(user)
            db.session.commit()
        cls.client = cls.app.test_client()

    @classmethod
    def tearDownClass(cls):
        if cls._prev_db_uri is None:
            os.environ.pop("SQLALCHEMY_DATABASE_URI", None)
        else:
            os.environ["SQLALCHEMY_DATABASE_URI"] = cls._prev_db_uri
        if cls._prev_db_url is None:
            os.environ.pop("DATABASE_URL", None)
        else:
            os.environ["DATABASE_URL"] = cls._prev_db_url
        if cls._prev_env is None:
            os.environ.pop("FLIPTRYBE_ENV", None)
        else:
            os.environ["FLIPTRYBE_ENV"] = cls._prev_env
        if cls._prev_termii is None:
            os.environ.pop("TERMII_API_KEY", None)
        else:
            os.environ["TERMII_API_KEY"] = cls._prev_termii

    def test_request_phone_otp_returns_demo_code_in_dev(self):
        res = self.client.post("/api/auth/otp/request", json={"phone": "+2348100002000"})
        self.assertEqual(res.status_code, 200)
        payload = res.get_json() or {}
        self.assertTrue(payload.get("ok"))
        self.assertIn("demo_otp", payload)
        self.assertEqual(len(str(payload.get("demo_otp") or "")), 6)

    def test_verify_phone_otp_marks_user_verified_and_returns_session(self):
        request_res = self.client.post("/api/auth/otp/request", json={"phone": "+2348100002000"})
        self.assertEqual(request_res.status_code, 200)
        request_payload = request_res.get_json() or {}
        code = str(request_payload.get("demo_otp") or "")
        self.assertEqual(len(code), 6)

        verify_res = self.client.post(
            "/api/auth/otp/verify",
            json={"phone": "+2348100002000", "code": code},
        )
        self.assertEqual(verify_res.status_code, 200)
        verify_payload = verify_res.get_json() or {}
        self.assertTrue(verify_payload.get("ok"))
        self.assertTrue(verify_payload.get("verified"))
        self.assertTrue(str(verify_payload.get("token") or "").strip())
        self.assertTrue(str(verify_payload.get("refresh_token") or "").strip())

        with self.app.app_context():
            user = User.query.filter_by(phone="+2348100002000").first()
            self.assertIsNotNone(user)
            self.assertTrue(bool(getattr(user, "is_verified", False)))


if __name__ == "__main__":
    unittest.main()
