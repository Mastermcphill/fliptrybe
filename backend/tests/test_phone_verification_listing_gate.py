from __future__ import annotations

import os
import unittest

from app import create_app
from app.extensions import db
from app.models import User
from app.utils.jwt_utils import create_token


class PhoneVerificationListingGateTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._prev_db_uri = os.getenv("SQLALCHEMY_DATABASE_URI")
        cls._prev_db_url = os.getenv("DATABASE_URL")
        db_uri = "sqlite:///:memory:"
        os.environ["SQLALCHEMY_DATABASE_URI"] = db_uri
        os.environ["DATABASE_URL"] = db_uri

        cls.app = create_app()
        cls.app.config.update(TESTING=True)

        with cls.app.app_context():
            db.create_all()

            verified = User(
                name="Verified Merchant",
                email="verified-merchant@fliptrybe.dev",
                phone="2348100011000",
                role="merchant",
                is_verified=True,
            )
            verified.set_password("password123")
            db.session.add(verified)

            unverified = User(
                name="Unverified Merchant",
                email="unverified-merchant@fliptrybe.dev",
                phone="2348100011001",
                role="merchant",
                is_verified=False,
            )
            unverified.set_password("password123")
            db.session.add(unverified)

            db.session.commit()

            cls.verified_token = create_token(int(verified.id))
            cls.unverified_token = create_token(int(unverified.id))

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

    def _create_listing(self, token: str):
        return self.client.post(
            "/api/listings",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "title": "Phone Gate Listing",
                "description": "Gate verification test",
                "price": 25000,
                "category": "General",
            },
        )

    def test_phone_verified_user_can_create_listing(self):
        res = self._create_listing(self.verified_token)
        self.assertEqual(res.status_code, 201)
        payload = res.get_json() or {}
        self.assertTrue(payload.get("ok"))

    def test_phone_not_verified_blocks_listing_creation(self):
        res = self._create_listing(self.unverified_token)
        self.assertEqual(res.status_code, 403)
        payload = res.get_json() or {}
        self.assertEqual(payload.get("error"), "PHONE_NOT_VERIFIED")


if __name__ == "__main__":
    unittest.main()
