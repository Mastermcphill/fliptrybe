from __future__ import annotations

import os
import time
import unittest
from datetime import datetime

from app import create_app
from app.extensions import db
from app.models import SupportMessage, User
from app.utils.jwt_utils import create_token


class AdminSupportReplyTestCase(unittest.TestCase):
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

    def _seed_user(self, role: str) -> User:
        suffix = str(time.time_ns())
        row = User(
            name=f"{role}-{suffix[-4:]}",
            email=f"{role}-{suffix}@fliptrybe.test",
            phone=f"080{suffix[-8:]}",
            role=role,
            is_verified=True,
        )
        row.set_password("Passw0rd!")
        db.session.add(row)
        db.session.commit()
        return row

    def test_admin_can_reply_and_user_receives_same_thread(self):
        with self.app.app_context():
            buyer = self._seed_user("buyer")
            admin = self._seed_user("admin")
            buyer_id = int(buyer.id)
            admin_id = int(admin.id)
            db.session.add(
                SupportMessage(
                    user_id=buyer_id,
                    sender_role="user",
                    sender_id=buyer_id,
                    body="Need help with payment",
                    created_at=datetime.utcnow(),
                )
            )
            db.session.commit()
            buyer_token = create_token(buyer_id)
            admin_token = create_token(admin_id)

        reply = self.client.post(
            f"/api/admin/support/threads/{buyer_id}/messages",
            headers={"Authorization": f"Bearer {admin_token}"},
            json={"body": "Support team is on it."},
        )
        self.assertEqual(reply.status_code, 201)
        reply_json = reply.get_json(force=True) or {}
        self.assertTrue(reply_json.get("ok"))
        msg = reply_json.get("message") or {}
        self.assertEqual(msg.get("sender_role"), "admin")
        self.assertEqual(int(msg.get("thread_id") or 0), buyer_id)
        self.assertEqual(int(msg.get("sender_user_id") or 0), admin_id)

        admin_thread = self.client.get(
            f"/api/admin/support/threads/{buyer_id}/messages",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        self.assertEqual(admin_thread.status_code, 200)
        admin_items = (admin_thread.get_json(force=True) or {}).get("items") or []
        self.assertTrue(any((it.get("body") == "Support team is on it." and it.get("sender_role") == "admin") for it in admin_items))

        user_thread = self.client.get(
            "/api/support/messages",
            headers={"Authorization": f"Bearer {buyer_token}"},
        )
        self.assertEqual(user_thread.status_code, 200)
        user_items = (user_thread.get_json(force=True) or {}).get("items") or []
        self.assertTrue(any((it.get("body") == "Support team is on it." and it.get("sender_role") == "admin") for it in user_items))

    def test_non_admin_cannot_reply(self):
        with self.app.app_context():
            buyer = self._seed_user("buyer")
            other_user = self._seed_user("merchant")
            buyer_id = int(buyer.id)
            user_token = create_token(int(other_user.id))

        res = self.client.post(
            f"/api/admin/support/threads/{buyer_id}/messages",
            headers={"Authorization": f"Bearer {user_token}"},
            json={"body": "Impersonating admin"},
        )
        self.assertEqual(res.status_code, 403)


if __name__ == "__main__":
    unittest.main()
