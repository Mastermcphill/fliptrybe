from __future__ import annotations

import unittest
import uuid
import os

from app import create_app
from app.extensions import db


class RequestIdHeadersTestCase(unittest.TestCase):
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

    def test_generates_request_id_when_missing(self):
        res = self.client.get("/api/health")
        self.assertEqual(res.status_code, 200)
        rid = (res.headers.get("X-Request-ID") or "").strip()
        self.assertTrue(rid)
        uuid.UUID(rid)

    def test_echoes_request_id_when_provided(self):
        incoming = "rid-test-123"
        res = self.client.get("/api/health", headers={"X-Request-ID": incoming})
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.headers.get("X-Request-ID"), incoming)

    def test_error_payload_includes_trace_id(self):
        res = self.client.post("/api/listings", json={"title": "Missing auth"})
        self.assertEqual(res.status_code, 401)
        body = res.get_json(force=True)
        self.assertIsInstance(body, dict)
        self.assertIn("trace_id", body)
        self.assertEqual((body.get("trace_id") or "").strip(), (res.headers.get("X-Request-ID") or "").strip())


if __name__ == "__main__":
    unittest.main()
