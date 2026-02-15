from __future__ import annotations

import unittest
from datetime import datetime
from uuid import uuid4

from app import create_app
from app.extensions import db
from app.models import Notification, PayoutRequest, User, Wallet
from app.utils.jwt_utils import create_token


class WiringSyncEndpointsTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()
        cls.client = cls.app.test_client()

    def _headers(self, token: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {token}"}

    def _create_user(self, role: str, email_prefix: str) -> User:
        user = User(
            name=f"{role.title()} User",
            email=f"{email_prefix}-{uuid4().hex[:8]}@fliptrybe.test",
            role=role,
            password_hash="hashed-password",
            is_verified=True,
        )
        db.session.add(user)
        db.session.commit()
        return user

    def test_admin_pay_alias_processes_for_admin_and_blocks_non_admin(self):
        with self.app.app_context():
            admin = self._create_user("admin", "admin")
            buyer = self._create_user("buyer", "buyer")
            wallet = Wallet(user_id=int(buyer.id), balance=500.0, reserved_balance=0.0, currency="NGN")
            db.session.add(wallet)
            db.session.commit()

            payout = PayoutRequest(
                user_id=int(buyer.id),
                amount=100.0,
                fee_amount=0.0,
                net_amount=100.0,
                speed="standard",
                status="pending",
                updated_at=datetime.utcnow(),
            )
            db.session.add(payout)
            db.session.commit()
            payout_id = int(payout.id)
            admin_token = create_token(int(admin.id))
            buyer_token = create_token(int(buyer.id))

        forbidden = self.client.post(
            f"/api/wallet/payouts/{payout_id}/admin/pay",
            headers=self._headers(buyer_token),
        )
        self.assertEqual(forbidden.status_code, 403)

        ok = self.client.post(
            f"/api/wallet/payouts/{payout_id}/admin/pay",
            headers=self._headers(admin_token),
        )
        self.assertEqual(ok.status_code, 200)
        body = ok.get_json(force=True)
        self.assertTrue(body.get("ok"))
        self.assertEqual((body.get("payout") or {}).get("status"), "paid")

    def test_notification_mark_read_endpoint(self):
        with self.app.app_context():
            user = self._create_user("buyer", "notify")
            note = Notification(
                user_id=int(user.id),
                channel="in_app",
                title="Hello",
                message="Unread message",
                status="sent",
            )
            db.session.add(note)
            db.session.commit()
            note_id = int(note.id)
            token = create_token(int(user.id))

        unauthorized = self.client.post(f"/api/notifications/{note_id}/read")
        self.assertEqual(unauthorized.status_code, 401)

        marked = self.client.post(
            f"/api/notifications/{note_id}/read",
            headers=self._headers(token),
        )
        self.assertEqual(marked.status_code, 200)
        payload = marked.get_json(force=True)
        self.assertTrue(payload.get("ok"))
        self.assertTrue(payload.get("is_read"))
        self.assertTrue(str(payload.get("read_at") or "").strip())

        listed = self.client.get("/api/notifications", headers=self._headers(token))
        self.assertEqual(listed.status_code, 200)
        listed_body = listed.get_json(force=True)
        items = listed_body.get("items") or []
        row = next((item for item in items if int(item.get("id") or 0) == note_id), None)
        self.assertIsNotNone(row)
        self.assertTrue(bool(row.get("is_read")))
        self.assertTrue(str(row.get("read_at") or "").strip())

    def test_notification_mark_read_rejects_non_numeric_id_with_json(self):
        with self.app.app_context():
            user = self._create_user("buyer", "notify-bad-id")
            token = create_token(int(user.id))

        res = self.client.post(
            "/api/notifications/local-demo-id/read",
            headers=self._headers(token),
        )
        self.assertEqual(res.status_code, 404)
        body = res.get_json(force=True) or {}
        self.assertEqual((body.get("message") or "").lower(), "not found")
        self.assertTrue(str(body.get("trace_id") or "").strip())


if __name__ == "__main__":
    unittest.main()
