from __future__ import annotations

import os
import time
import unittest
from datetime import datetime
from unittest.mock import patch

from app import create_app
from app.extensions import db
from app.models import Listing, User
from app.services.search.meili_client import MeiliApiError, SearchUnavailable
from app.tasks.search_tasks import search_index_listing
from app.utils.jwt_utils import create_token


class _FakeMeiliClient:
    def __init__(
        self,
        *,
        hits: list[dict] | None = None,
        fail_search: bool = False,
        missing_index_on_search: bool = False,
        existing_indexes: set[str] | None = None,
    ):
        self._hits = list(hits or [])
        self._fail_search = bool(fail_search)
        self._missing_index_on_search = bool(missing_index_on_search)
        self.indexes = set(existing_indexes or {"listings_v1"})
        self.docs_by_id: dict[int, dict] = {}
        self.upsert_calls = 0
        self.ensure_calls: list[tuple[str, str]] = []
        self.configure_calls: list[str] = []
        self.operations: list[str] = []

    def search(self, index_name, q, filters, sort, limit, offset):
        if self._fail_search:
            raise SearchUnavailable("timeout")
        if self._missing_index_on_search:
            raise MeiliApiError(
                404,
                {
                    "code": "index_not_found",
                    "message": f"Index `{index_name}` not found.",
                },
            )
        safe_offset = max(0, int(offset or 0))
        safe_limit = max(1, int(limit or 20))
        page_hits = self._hits[safe_offset : safe_offset + safe_limit]
        return {
            "hits": page_hits,
            "estimatedTotalHits": len(self._hits),
            "offset": safe_offset,
            "limit": safe_limit,
        }

    def ensure_index(self, index_name, primary_key="id"):
        safe_name = str(index_name or "")
        safe_primary_key = str(primary_key or "id")
        self.ensure_calls.append((safe_name, safe_primary_key))
        self.operations.append(f"ensure:{safe_name}:{safe_primary_key}")
        self.indexes.add(safe_name)
        return {"uid": safe_name, "primaryKey": safe_primary_key}

    def configure_listings_index(self, index_name):
        safe_name = str(index_name or "")
        self.configure_calls.append(safe_name)
        self.operations.append(f"configure:{safe_name}")
        if safe_name not in self.indexes:
            raise AssertionError("configure_listings_index called before ensure_index")
        return {"taskUid": 1}

    def upsert_documents(self, index_name, docs):
        self.upsert_calls += 1
        for doc in docs or []:
            try:
                doc_id = int(doc.get("id") or 0)
            except Exception:
                doc_id = 0
            if doc_id > 0:
                self.docs_by_id[doc_id] = dict(doc)
        return {"ok": True, "queued": True}

    def delete_document(self, index_name, doc_id):
        try:
            self.docs_by_id.pop(int(doc_id), None)
        except Exception:
            pass
        return {"ok": True}


class SearchMeiliIntegrationTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._saved_env = {
            "SQLALCHEMY_DATABASE_URI": os.getenv("SQLALCHEMY_DATABASE_URI"),
            "DATABASE_URL": os.getenv("DATABASE_URL"),
            "FLIPTRYBE_ENV": os.getenv("FLIPTRYBE_ENV"),
            "ENABLE_CACHE": os.getenv("ENABLE_CACHE"),
            "SEARCH_ENGINE": os.getenv("SEARCH_ENGINE"),
            "SEARCH_FALLBACK_SQL": os.getenv("SEARCH_FALLBACK_SQL"),
            "SEARCH_INDEX_LISTINGS": os.getenv("SEARCH_INDEX_LISTINGS"),
            "MEILI_HOST": os.getenv("MEILI_HOST"),
            "MEILI_API_KEY": os.getenv("MEILI_API_KEY"),
        }

        db_uri = "sqlite:///:memory:"
        os.environ["SQLALCHEMY_DATABASE_URI"] = db_uri
        os.environ["DATABASE_URL"] = db_uri
        os.environ["FLIPTRYBE_ENV"] = "dev"
        os.environ["ENABLE_CACHE"] = "false"
        os.environ["SEARCH_ENGINE"] = "meili"
        os.environ["SEARCH_FALLBACK_SQL"] = "true"
        os.environ["SEARCH_INDEX_LISTINGS"] = "listings_v1"
        os.environ["MEILI_HOST"] = "http://meili.invalid:7700"
        os.environ["MEILI_API_KEY"] = ""

        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        cls.client = cls.app.test_client()

    @classmethod
    def tearDownClass(cls):
        for key, value in cls._saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def setUp(self):
        os.environ["SEARCH_ENGINE"] = "meili"
        os.environ["SEARCH_FALLBACK_SQL"] = "true"
        with self.app.app_context():
            db.session.remove()
            db.drop_all()
            db.create_all()

    def _admin_headers(self) -> dict[str, str]:
        with self.app.app_context():
            suffix = str(time.time_ns())
            admin = User(
                name=f"Admin {suffix[-4:]}",
                email=f"admin-{suffix}@fliptrybe.test",
                phone=f"080{suffix[-8:]}",
                role="admin",
                is_verified=True,
            )
            admin.set_password("Passw0rd!")
            db.session.add(admin)
            db.session.commit()
            token = create_token(int(admin.id))
        return {"Authorization": f"Bearer {token}"}

    def _create_listing(self, *, title: str, description: str = "searchable listing") -> int:
        with self.app.app_context():
            row = Listing(
                title=title,
                description=description,
                category="declutter",
                listing_type="declutter",
                approval_status="approved",
                state="Lagos",
                city="Ikeja",
                price=250000.0,
                base_price=250000.0,
                platform_fee=0.0,
                final_price=250000.0,
                image_path="",
                is_active=True,
                created_at=datetime.utcnow(),
                date_posted=datetime.utcnow(),
            )
            db.session.add(row)
            db.session.commit()
            return int(row.id)

    def test_listings_search_uses_meili_when_enabled(self):
        listing_id = self._create_listing(title="Meili Primary Path")
        fake = _FakeMeiliClient(
            hits=[
                {
                    "id": listing_id,
                    "title": "Meili Primary Path",
                    "description": "served from meili",
                    "category": "declutter",
                    "listing_type": "declutter",
                    "state": "Lagos",
                    "city": "Ikeja",
                    "price": 250000,
                    "final_price": 250000,
                    "approval_status": "approved",
                    "is_active": True,
                    "created_at": datetime.utcnow().isoformat(),
                }
            ]
        )
        with patch("app.segments.segment_market.get_meili_client", return_value=fake), patch(
            "app.segments.segment_market._run_sql_search",
            side_effect=AssertionError("SQL fallback should not run for healthy meili"),
        ):
            res = self.client.get("/api/listings/search?q=meili&limit=10&offset=0")

        self.assertEqual(res.status_code, 200)
        payload = res.get_json(force=True) or {}
        self.assertTrue(bool(payload.get("ok")))
        items = payload.get("items") or []
        self.assertEqual(len(items), 1)
        self.assertEqual(int(items[0].get("id") or 0), listing_id)

    def test_listings_search_falls_back_to_sql_when_meili_unavailable(self):
        listing_id = self._create_listing(title="Fallback SQL Meili Down")
        os.environ["SEARCH_FALLBACK_SQL"] = "true"

        with patch("app.segments.segment_market.get_meili_client", side_effect=SearchUnavailable("down")):
            res = self.client.get("/api/listings/search?q=Fallback%20SQL%20Meili%20Down&limit=10")

        self.assertEqual(res.status_code, 200)
        payload = res.get_json(force=True) or {}
        self.assertTrue(bool(payload.get("ok")))
        items = payload.get("items") or []
        self.assertTrue(any(int(item.get("id") or 0) == listing_id for item in items))

    def test_listings_search_returns_503_when_fallback_disabled_and_meili_down(self):
        self._create_listing(title="No SQL fallback listing")
        os.environ["SEARCH_FALLBACK_SQL"] = "false"

        with patch("app.segments.segment_market.get_meili_client", side_effect=SearchUnavailable("timeout")):
            res = self.client.get("/api/listings/search?q=No%20SQL%20fallback")

        self.assertEqual(res.status_code, 503)
        payload = res.get_json(force=True) or {}
        error = payload.get("error") or {}
        self.assertEqual(error.get("code"), "SEARCH_UNAVAILABLE")
        self.assertTrue((payload.get("trace_id") or "").strip())

    def test_listings_search_returns_400_when_meili_index_missing(self):
        os.environ["SEARCH_FALLBACK_SQL"] = "false"
        fake = _FakeMeiliClient(missing_index_on_search=True)

        with patch("app.segments.segment_market.get_meili_client", return_value=fake):
            res = self.client.get("/api/listings/search?q=needs-init")

        self.assertEqual(res.status_code, 400)
        payload = res.get_json(force=True) or {}
        error = payload.get("error") or {}
        self.assertEqual(error.get("code"), "SEARCH_NOT_INITIALIZED")
        self.assertTrue((payload.get("trace_id") or "").strip())

    def test_admin_search_init_creates_index_when_missing(self):
        fake = _FakeMeiliClient(existing_indexes=set())
        headers = self._admin_headers()

        with patch("app.segments.segment_admin_ops.get_meili_client", return_value=fake):
            res = self.client.post("/api/admin/search/init", headers=headers, json={})

        self.assertEqual(res.status_code, 200)
        payload = res.get_json(force=True) or {}
        self.assertTrue(bool(payload.get("ok")))
        self.assertEqual(payload.get("index_name"), "listings_v1")
        self.assertTrue(bool(payload.get("settings_applied")))
        self.assertIn("listings_v1", fake.indexes)
        self.assertEqual(fake.operations[0], "ensure:listings_v1:id")
        self.assertEqual(fake.operations[1], "configure:listings_v1")

    def test_admin_search_init_is_idempotent(self):
        fake = _FakeMeiliClient(existing_indexes=set())
        headers = self._admin_headers()

        with patch("app.segments.segment_admin_ops.get_meili_client", return_value=fake):
            first = self.client.post("/api/admin/search/init", headers=headers, json={})
            second = self.client.post("/api/admin/search/init", headers=headers, json={})

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        first_payload = first.get_json(force=True) or {}
        second_payload = second.get_json(force=True) or {}
        self.assertTrue(bool(first_payload.get("ok")))
        self.assertTrue(bool(second_payload.get("ok")))
        self.assertEqual(first_payload.get("index_name"), "listings_v1")
        self.assertEqual(second_payload.get("index_name"), "listings_v1")
        self.assertTrue(bool(first_payload.get("settings_applied")))
        self.assertTrue(bool(second_payload.get("settings_applied")))
        self.assertEqual(fake.ensure_calls.count(("listings_v1", "id")), 2)
        self.assertEqual(fake.configure_calls.count("listings_v1"), 2)
        self.assertEqual(fake.indexes, {"listings_v1"})

    def test_search_index_listing_task_is_idempotent(self):
        listing_id = self._create_listing(title="Idempotent Indexing")
        os.environ["SEARCH_ENGINE"] = "meili"

        fake = _FakeMeiliClient()
        with self.app.app_context():
            with patch("app.tasks.search_tasks.get_meili_client", return_value=fake):
                first = search_index_listing.run(listing_id=listing_id, trace_id="trace-a")
                second = search_index_listing.run(listing_id=listing_id, trace_id="trace-b")

        self.assertTrue(bool(first.get("ok")))
        self.assertTrue(bool(second.get("ok")))
        self.assertEqual(fake.upsert_calls, 2)
        self.assertEqual(len(fake.docs_by_id), 1)
        self.assertIn(int(listing_id), fake.docs_by_id)


if __name__ == "__main__":
    unittest.main()
