from __future__ import annotations

import time
import unittest
from datetime import datetime

from app import create_app
from app.extensions import db
from app.models import RoleChangeRequest, User


class InspectorAuthFlowTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()
        cls.client = cls.app.test_client()

    def _unique_suffix(self) -> str:
        return str(int(time.time() * 1000000))

    def _register_inspector(self) -> tuple[dict, str, str]:
        suffix = self._unique_suffix()
        email = f'inspector-{suffix}@fliptrybe.test'
        phone = f'0803{suffix[-7:]}'
        password = 'Passw0rd!'
        payload = {
            'name': 'Inspector Candidate',
            'email': email,
            'password': password,
            'phone': phone,
            'state': 'Lagos',
            'city': 'Lagos',
            'region': 'Ikeja',
            'reason': 'Inspection experience',
        }
        res = self.client.post('/api/auth/register/inspector', json=payload)
        self.assertEqual(res.status_code, 201)
        body = res.get_json(force=True)
        self.assertIn('token', body)
        self.assertIn('user', body)
        return body, email, password

    def _auth_headers(self, token: str) -> dict[str, str]:
        return {'Authorization': f'Bearer {token}'}

    def test_register_login_me_and_pending_status(self):
        register_body, email, password = self._register_inspector()

        login_res = self.client.post(
            '/api/auth/login',
            json={'email': email, 'password': password},
        )
        self.assertEqual(login_res.status_code, 200)
        login_body = login_res.get_json(force=True)
        token = login_body.get('token')
        self.assertTrue(isinstance(token, str) and token)

        me_res = self.client.get('/api/auth/me', headers=self._auth_headers(token))
        self.assertEqual(me_res.status_code, 200)
        me = me_res.get_json(force=True)
        self.assertEqual((me.get('role') or '').lower(), 'buyer')
        self.assertEqual((me.get('role_status') or '').lower(), 'pending')
        self.assertEqual((me.get('requested_role') or '').lower(), 'inspector')

        role_req_res = self.client.get(
            '/api/role-requests/me',
            headers=self._auth_headers(token),
        )
        self.assertEqual(role_req_res.status_code, 200)
        req_body = role_req_res.get_json(force=True)
        self.assertTrue(req_body.get('ok'))
        req = req_body.get('request') or {}
        self.assertEqual((req.get('status') or '').lower(), 'pending')
        self.assertEqual((req.get('requested_role') or '').lower(), 'inspector')

        inspector_only = self.client.get(
            '/api/inspectors/me/profile',
            headers=self._auth_headers(token),
        )
        self.assertEqual(inspector_only.status_code, 403)

        self.assertEqual(
            ((register_body.get('user') or {}).get('role_status') or '').lower(),
            'pending',
        )

    def test_pending_then_approved_unlocks_inspector_endpoint(self):
        register_body, _, _ = self._register_inspector()
        token = (register_body.get('token') or '').strip()
        user_id = int((register_body.get('user') or {}).get('id') or 0)
        self.assertGreater(user_id, 0)

        with self.app.app_context():
            user = User.query.get(int(user_id))
            self.assertIsNotNone(user)
            user.role = 'inspector'
            req = (
                RoleChangeRequest.query.filter_by(user_id=int(user_id), requested_role='inspector')
                .order_by(RoleChangeRequest.created_at.desc())
                .first()
            )
            self.assertIsNotNone(req)
            req.status = 'APPROVED'
            req.decided_at = datetime.utcnow()
            db.session.add(user)
            db.session.add(req)
            db.session.commit()

        inspector_only = self.client.get(
            '/api/inspectors/me/profile',
            headers=self._auth_headers(token),
        )
        self.assertEqual(inspector_only.status_code, 200)
        body = inspector_only.get_json(force=True)
        self.assertTrue(body.get('ok'))


if __name__ == '__main__':
    unittest.main()
