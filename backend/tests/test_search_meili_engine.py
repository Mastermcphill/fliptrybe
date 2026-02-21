from __future__ import annotations

import os
import time
import unittest
from datetime import datetime
from unittest.mock import patch

from app import create_app
from app.extensions import db
from app.models import Listing, User
from app.services.search.meili_client import MeiliClient, SearchNotInitialized, SearchUnavailable
from app.tasks.search_tasks import search_index_listing
from ops.check_celery_import import main as celery_import_check_main
from app.utils.jwt_utils import create_token


class _FakeMeiliClient:
    def __init__(
        self,
        *,
        hits: list[dict] | None = None,
        fail_search: bool = False,
        fail_health: bool = False,
        search_not_initialized: bool = False,
        existing_indexes: set[str] | None = None,
        document_count: int = 0,
        settings: dict | None = None,
        version: str = "1.11.0",
        global_stats: dict | None = None,
        index_meta: dict | None = None,
    ):
        self._hits = list(hits or [])
        self._fail_search = bool(fail_search)
        self._fail_health = bool(fail_health)
        self._search_not_initialized = bool(search_not_initialized)
        self.indexes = set(existing_indexes) if existing_indexes is not None else {"listings_v1"}
        self._document_count = int(max(0, int(document_count or 0)))
        self._settings = dict(
            settings
            or {
                "searchableAttributes": [],
                "filterableAttributes": [],
                "sortableAttributes": [],
            }
        )
        self._version = str(version or "")
        self._global_stats = dict(global_stats or {})
        self._index_meta = dict(index_meta or {})
        self.create_calls = 0
        self.docs_by_id: dict[int, dict] = {}
        self.upsert_calls = 0
        self.ensure_calls: list[tuple[str, str]] = []
        self.configure_calls: list[str] = []
        self.operations: list[str] = []

    def get_health(self):
        if self._fail_health:
            raise SearchUnavailable("connection refused")
        return {"status": "available"}

    def get_version(self):
        return {"pkgVersion": self._version}

    def get_stats(self):
        payload = {"databaseSize": 0}
        payload.update(self._global_stats)
        return payload

    def index_exists(self, index_name):
        return str(index_name or "") in self.indexes

    def get_index(self, index_name):
        safe_name = str(index_name or "")
        if safe_name not in self.indexes:
            raise SearchNotInitialized(safe_name)
        payload = {"uid": safe_name}
        payload.update(self._index_meta)
        return payload

    def get_index_stats(self, index_name):
        safe_name = str(index_name or "")
        if safe_name not in self.indexes:
            raise SearchNotInitialized(safe_name)
        return {"numberOfDocuments": int(self._document_count)}

    def get_index_settings(self, index_name):
        safe_name = str(index_name or "")
        if safe_name not in self.indexes:
            raise SearchNotInitialized(safe_name)
        return dict(self._settings)

    def search(self, index_name, q, filters, sort, limit, offset):
        if self._fail_search:
            raise SearchUnavailable("timeout")
        if self._search_not_initialized:
            raise SearchNotInitialized(str(index_name or ""))
        q_text = str(q or "").strip().lower()
        if self._hits:
            source_hits = [dict(row) for row in self._hits if isinstance(row, dict)]
        else:
            source_hits = [dict(row) for _, row in sorted(self.docs_by_id.items(), key=lambda pair: pair[0])]
        if q_text:
            filtered_hits: list[dict] = []
            for row in source_hits:
                haystack = " ".join(
                    [
                        str(row.get("title") or ""),
                        str(row.get("description") or ""),
                        str(row.get("city") or ""),
                        str(row.get("state") or ""),
                        str(row.get("category") or ""),
                    ]
                ).lower()
                if q_text in haystack:
                    filtered_hits.append(row)
            source_hits = filtered_hits
        safe_offset = max(0, int(offset or 0))
        safe_limit = max(1, int(limit or 20))
        page_hits = source_hits[safe_offset : safe_offset + safe_limit]
        return {
            "hits": page_hits,
            "estimatedTotalHits": len(source_hits),
            "offset": safe_offset,
            "limit": safe_limit,
        }

    def ensure_index(self, index_name, primary_key="id"):
        safe_name = str(index_name or "")
        safe_primary_key = str(primary_key or "id")
        self.ensure_calls.append((safe_name, safe_primary_key))
        self.operations.append(f"ensure:{safe_name}:{safe_primary_key}")
        if safe_name not in self.indexes:
            self.create_calls += 1
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
        self._document_count = int(len(self.docs_by_id))
        return {"ok": True, "queued": True}

    def delete_document(self, index_name, doc_id):
        try:
            self.docs_by_id.pop(int(doc_id), None)
        except Exception:
            pass
        self._document_count = int(len(self.docs_by_id))
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
        fake = _FakeMeiliClient(search_not_initialized=True)

        with patch("app.segments.segment_market.get_meili_client", return_value=fake):
            res = self.client.get("/api/listings/search?q=needs-init")

        self.assertEqual(res.status_code, 400)
        payload = res.get_json(force=True) or {}
        self.assertEqual(payload.get("error"), "SEARCH_NOT_INITIALIZED")
        self.assertTrue((payload.get("trace_id") or "").strip())

    def test_listings_search_falls_back_to_sql_when_index_missing_and_fallback_enabled(self):
        listing_id = self._create_listing(title="Fallback SQL Init Needed")
        os.environ["SEARCH_FALLBACK_SQL"] = "true"
        fake = _FakeMeiliClient(search_not_initialized=True)

        with patch("app.segments.segment_market.get_meili_client", return_value=fake):
            res = self.client.get("/api/listings/search?q=Fallback%20SQL%20Init%20Needed&limit=10")

        self.assertEqual(res.status_code, 200)
        payload = res.get_json(force=True) or {}
        self.assertTrue(bool(payload.get("ok")))
        items = payload.get("items") or []
        self.assertTrue(any(int(item.get("id") or 0) == listing_id for item in items))

    def test_listing_update_rejects_malformed_json_without_db_change(self):
        listing_id = self._create_listing(title="Seed Listing")
        headers = self._admin_headers()
        response = self.client.put(
            f"/api/listings/{listing_id}",
            headers=headers,
            data='{"title": "Broken JSON"',
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)
        payload = response.get_json(force=True) or {}
        self.assertEqual(payload.get("error"), "INVALID_JSON")
        with self.app.app_context():
            listing = db.session.get(Listing, int(listing_id))
            self.assertIsNotNone(listing)
            self.assertEqual(str(getattr(listing, "title", "") or ""), "Seed Listing")

    def test_listing_update_rejects_empty_payload_without_db_change(self):
        listing_id = self._create_listing(title="Seed Listing")
        headers = self._admin_headers()
        response = self.client.put(
            f"/api/listings/{listing_id}",
            headers=headers,
            json={},
        )

        self.assertEqual(response.status_code, 400)
        payload = response.get_json(force=True) or {}
        self.assertEqual(payload.get("error"), "EMPTY_UPDATE")
        with self.app.app_context():
            listing = db.session.get(Listing, int(listing_id))
            self.assertIsNotNone(listing)
            self.assertEqual(str(getattr(listing, "title", "") or ""), "Seed Listing")

    def test_listing_update_triggers_meili_indexing(self):
        listing_id = self._create_listing(title="Seed Listing")
        headers = self._admin_headers()
        os.environ["SEARCH_ENGINE"] = "meili"
        os.environ["SEARCH_FALLBACK_SQL"] = "false"
        fake = _FakeMeiliClient(existing_indexes={"listings_v1"})

        def _delay_inline(listing_id, trace_id=""):
            return search_index_listing.run(listing_id=int(listing_id), trace_id=str(trace_id or ""))

        with patch("app.segments.segment_market.get_meili_client", return_value=fake), patch(
            "app.tasks.search_tasks.get_meili_client",
            return_value=fake,
        ), patch(
            "app.tasks.search_tasks.search_index_listing.delay",
            side_effect=_delay_inline,
        ):
            update_res = self.client.put(
                f"/api/listings/{listing_id}",
                headers=headers,
                json={"title": "ZEBRA-ALPHA-999"},
            )
            search_res = self.client.get("/api/listings/search?q=ZEBRA-ALPHA-999&limit=10&offset=0")

        self.assertEqual(update_res.status_code, 200)
        update_payload = update_res.get_json(force=True) or {}
        self.assertTrue(bool(update_payload.get("ok")))
        self.assertEqual((update_payload.get("listing") or {}).get("title"), "ZEBRA-ALPHA-999")
        self.assertGreaterEqual(int(fake.upsert_calls or 0), 1)
        self.assertIn(int(listing_id), fake.docs_by_id)
        self.assertEqual(str(fake.docs_by_id[int(listing_id)].get("title") or ""), "ZEBRA-ALPHA-999")

        self.assertEqual(search_res.status_code, 200)
        search_payload = search_res.get_json(force=True) or {}
        self.assertTrue(bool(search_payload.get("ok")))
        items = search_payload.get("items") or []
        self.assertTrue(any(str(item.get("title") or "") == "ZEBRA-ALPHA-999" for item in items))

    def test_listing_update_without_meili_falls_back_sql_when_enabled(self):
        listing_id = self._create_listing(title="Fallback After Update")
        headers = self._admin_headers()
        os.environ["SEARCH_ENGINE"] = "meili"
        os.environ["SEARCH_FALLBACK_SQL"] = "true"

        with patch(
            "app.tasks.search_tasks.search_index_listing.delay",
            side_effect=RuntimeError("simulated enqueue failure"),
        ):
            update_res = self.client.put(
                f"/api/listings/{listing_id}",
                headers=headers,
                json={"title": "Fallback SQL Updated 321"},
            )

        with patch("app.segments.segment_market.get_meili_client", side_effect=SearchUnavailable("down")):
            search_res = self.client.get("/api/listings/search?q=Fallback%20SQL%20Updated%20321&limit=10")

        self.assertEqual(update_res.status_code, 200)
        update_payload = update_res.get_json(force=True) or {}
        self.assertTrue(bool(update_payload.get("ok")))
        self.assertEqual((update_payload.get("listing") or {}).get("title"), "Fallback SQL Updated 321")
        self.assertEqual(search_res.status_code, 200)
        search_payload = search_res.get_json(force=True) or {}
        self.assertTrue(bool(search_payload.get("ok")))
        items = search_payload.get("items") or []
        self.assertTrue(any(int(item.get("id") or 0) == int(listing_id) for item in items))

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
        self.assertEqual(fake.create_calls, 1)
        self.assertEqual(fake.indexes, {"listings_v1"})

    def test_reindex_ensures_index_before_enqueue(self):
        fake = _FakeMeiliClient(existing_indexes=set())
        headers = self._admin_headers()

        class _FakeTaskResult:
            id = "task-123"

        with patch("app.segments.segment_admin_ops.get_meili_client", return_value=fake), patch(
            "app.tasks.search_tasks.search_reindex_all.delay",
            return_value=_FakeTaskResult(),
        ) as delay_mock:
            res = self.client.post("/api/admin/search/reindex", headers=headers, json={"batch_size": 50})

        self.assertEqual(res.status_code, 202)
        self.assertGreaterEqual(len(fake.operations), 1)
        self.assertEqual(fake.operations[0], "ensure:listings_v1:id")
        delay_mock.assert_called_once()

    def test_search_status_when_engine_disabled(self):
        headers = self._admin_headers()
        os.environ["SEARCH_ENGINE"] = "sql"

        res = self.client.get("/api/admin/search/status", headers=headers)

        self.assertEqual(res.status_code, 200)
        payload = res.get_json(force=True) or {}
        self.assertTrue(bool(payload.get("ok")))
        self.assertEqual(payload.get("engine"), "disabled")
        self.assertEqual(payload.get("index_name"), "listings_v1")
        self.assertFalse(bool(payload.get("index_exists")))
        self.assertEqual(int(payload.get("document_count") or 0), 0)
        self.assertEqual(payload.get("index_uid"), "listings_v1")
        self.assertIn("meili_version", payload)
        self.assertIn("databaseSize", payload)
        self.assertIn("lastUpdate", payload)

    def test_search_status_index_missing(self):
        headers = self._admin_headers()
        os.environ["SEARCH_ENGINE"] = "meili"
        fake = _FakeMeiliClient(existing_indexes=set())

        with patch("app.segments.segment_admin_ops.get_meili_client", return_value=fake):
            res = self.client.get("/api/admin/search/status", headers=headers)

        self.assertEqual(res.status_code, 200)
        payload = res.get_json(force=True) or {}
        self.assertTrue(bool(payload.get("ok")))
        self.assertEqual(payload.get("engine"), "meili")
        self.assertTrue(bool((payload.get("health") or {}).get("reachable")))
        self.assertFalse(bool(payload.get("index_exists")))
        self.assertEqual(int(payload.get("document_count") or 0), 0)
        self.assertEqual(payload.get("index_uid"), "listings_v1")
        self.assertEqual(payload.get("meili_version"), "1.11.0")
        self.assertEqual(int(payload.get("databaseSize") or 0), 0)

    def test_search_status_index_present(self):
        headers = self._admin_headers()
        os.environ["SEARCH_ENGINE"] = "meili"
        fake_settings = {
            "searchableAttributes": ["title", "description"],
            "filterableAttributes": ["category", "city"],
            "sortableAttributes": ["price", "created_at"],
        }
        fake = _FakeMeiliClient(
            existing_indexes={"listings_v1"},
            document_count=34,
            settings=fake_settings,
            global_stats={"databaseSize": 2048, "lastUpdate": "2026-02-20T12:00:00Z"},
            index_meta={"uid": "listings_v1", "updatedAt": "2026-02-20T12:00:00Z"},
        )

        with patch("app.segments.segment_admin_ops.get_meili_client", return_value=fake):
            res = self.client.get("/api/admin/search/status", headers=headers)

        self.assertEqual(res.status_code, 200)
        payload = res.get_json(force=True) or {}
        self.assertTrue(bool(payload.get("ok")))
        self.assertEqual(payload.get("engine"), "meili")
        self.assertTrue(bool(payload.get("index_exists")))
        self.assertEqual(int(payload.get("document_count") or 0), 34)
        settings = payload.get("settings") or {}
        self.assertEqual(settings.get("searchableAttributes"), fake_settings["searchableAttributes"])
        self.assertEqual(settings.get("filterableAttributes"), fake_settings["filterableAttributes"])
        self.assertEqual(settings.get("sortableAttributes"), fake_settings["sortableAttributes"])
        self.assertEqual(payload.get("index_uid"), "listings_v1")
        self.assertEqual(payload.get("meili_version"), "1.11.0")
        self.assertEqual(int(payload.get("databaseSize") or 0), 2048)
        self.assertEqual(payload.get("lastUpdate"), "2026-02-20T12:00:00Z")

    def test_search_status_meili_unreachable(self):
        headers = self._admin_headers()
        os.environ["SEARCH_ENGINE"] = "meili"
        fake = _FakeMeiliClient(fail_health=True)

        with patch("app.segments.segment_admin_ops.get_meili_client", return_value=fake):
            res = self.client.get("/api/admin/search/status", headers=headers)

        self.assertEqual(res.status_code, 503)
        payload = res.get_json(force=True) or {}
        self.assertFalse(bool(payload.get("ok")))
        self.assertEqual(payload.get("engine"), "meili")
        self.assertEqual(payload.get("error"), "SEARCH_UNAVAILABLE")
        health = payload.get("health") or {}
        self.assertFalse(bool(health.get("reachable")))
        self.assertEqual(health.get("status"), "unreachable")

    def test_search_status_route_requires_auth_and_is_mounted(self):
        res = self.client.get("/api/admin/search/status")
        self.assertEqual(res.status_code, 401)

    def test_admin_ops_health_deps_requires_auth(self):
        res = self.client.get("/api/admin/ops/health-deps")
        self.assertEqual(res.status_code, 401)

    def test_admin_ops_health_deps_returns_200_with_admin(self):
        headers = self._admin_headers()
        os.environ["SEARCH_ENGINE"] = "sql"
        with patch.dict(os.environ, {"RATE_LIMIT_REDIS_URL": "", "CACHE_REDIS_URL": "", "REDIS_URL": ""}, clear=False):
            res = self.client.get("/api/admin/ops/health-deps", headers=headers)

        self.assertEqual(res.status_code, 200)
        payload = res.get_json(force=True) or {}
        self.assertIn("postgres", payload)
        self.assertIn("redis", payload)
        self.assertIn("meili", payload)

    def test_admin_ops_celery_status_requires_auth(self):
        res = self.client.get("/api/admin/ops/celery/status")
        self.assertEqual(res.status_code, 401)

    def test_admin_ops_celery_status_returns_200_with_admin(self):
        headers = self._admin_headers()
        with patch.dict(os.environ, {"CELERY_BROKER_URL": "", "REDIS_URL": ""}, clear=False):
            res = self.client.get("/api/admin/ops/celery/status", headers=headers)

        self.assertEqual(res.status_code, 200)
        payload = res.get_json(force=True) or {}
        self.assertTrue(bool(payload.get("ok")))
        self.assertFalse(bool(payload.get("broker_url_configured")))
        queue = payload.get("queue") or {}
        self.assertEqual(queue.get("name"), "celery")
        self.assertIn("status", queue)

    def test_meili_index_not_found_maps_to_search_not_initialized(self):
        class _FakeResponse:
            def __init__(self, status_code: int, payload: dict):
                self.status_code = int(status_code)
                self._payload = dict(payload)
                self.text = str(payload)

            def json(self):
                return dict(self._payload)

        response = _FakeResponse(
            404,
            {
                "message": "Index `listings_v1` not found.",
                "code": "index_not_found",
                "type": "invalid_request",
            },
        )
        with patch("requests.Session.request", return_value=response):
            client = MeiliClient(host="http://meili.invalid:7700", api_key="", timeout=0.1)
            with self.assertRaises(SearchNotInitialized) as raised:
                client.search("listings_v1", "chair", None, None, 20, 0)

        self.assertEqual(raised.exception.index_name, "listings_v1")

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

    def test_search_index_listing_retries_on_transient_meili_error(self):
        listing_id = self._create_listing(title="Retry listing")
        os.environ["SEARCH_ENGINE"] = "meili"

        class _FailingClient(_FakeMeiliClient):
            def upsert_documents(self, index_name, docs):
                raise SearchUnavailable("Meilisearch request timed out")

        with self.app.app_context():
            with patch("app.tasks.search_tasks.get_meili_client", return_value=_FailingClient()), patch.object(
                search_index_listing,
                "retry",
                side_effect=RuntimeError("retry-called"),
            ) as retry_mock:
                search_index_listing.request.retries = 0
                with self.assertRaises(RuntimeError):
                    search_index_listing.run(listing_id=listing_id, trace_id="trace_retry")

        retry_mock.assert_called_once()
        retry_kwargs = dict(retry_mock.call_args.kwargs or {})
        self.assertEqual(int(retry_kwargs.get("countdown") or 0), 5)

    def test_celery_import_check_passes(self):
        self.assertEqual(int(celery_import_check_main()), 0)


if __name__ == "__main__":
    unittest.main()
