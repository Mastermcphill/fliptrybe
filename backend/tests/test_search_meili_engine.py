from __future__ import annotations

import os
import unittest
from datetime import datetime
from unittest.mock import patch

from app import create_app
from app.extensions import db
from app.models import Listing
from app.services.search.meili_client import SearchUnavailable
from app.tasks.search_tasks import search_index_listing


class _FakeMeiliClient:
    def __init__(self, *, hits: list[dict] | None = None, fail_search: bool = False):
        self._hits = list(hits or [])
        self._fail_search = bool(fail_search)
        self.docs_by_id: dict[int, dict] = {}
        self.upsert_calls = 0

    def search(self, index_name, q, filters, sort, limit, offset):
        if self._fail_search:
            raise SearchUnavailable("timeout")
        safe_offset = max(0, int(offset or 0))
        safe_limit = max(1, int(limit or 20))
        page_hits = self._hits[safe_offset : safe_offset + safe_limit]
        return {
            "hits": page_hits,
            "estimatedTotalHits": len(self._hits),
            "offset": safe_offset,
            "limit": safe_limit,
        }

    def ensure_index(self, index_name):
        return {"uid": str(index_name)}

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
