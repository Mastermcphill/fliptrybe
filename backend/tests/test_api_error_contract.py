from __future__ import annotations

import unittest

from app import create_app


class ApiErrorContractTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        cls.client = cls.app.test_client()

    def test_unknown_api_route_returns_json_error_shape(self):
        res = self.client.get("/api/does-not-exist")
        self.assertEqual(res.status_code, 404)
        self.assertTrue(res.is_json)
        body = res.get_json(force=True) or {}
        self.assertFalse(bool(body.get("ok", True)))
        self.assertTrue(str(body.get("error") or "").strip())
        self.assertTrue(str(body.get("message") or "").strip())
        self.assertEqual(int(body.get("status") or 0), 404)
        self.assertTrue(str(body.get("trace_id") or "").strip())


if __name__ == "__main__":
    unittest.main()
