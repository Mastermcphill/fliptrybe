from __future__ import annotations

import json
import time
from datetime import datetime

from celery import shared_task
from flask import current_app

from app.models import Listing
from app.services.search import (
    listing_should_be_indexed,
    listing_to_search_document,
    listings_index_name,
    search_engine_is_meili,
)
from app.services.search.meili_client import SearchUnavailable, get_meili_client


def _retry_countdown(retries: int) -> int:
    return int(min(900, max(5, 5 * (2 ** int(max(0, retries))))))


def _task_log(task_name: str, *, status: str, started_at: float, trace_id: str = "", **extra):
    duration_ms = int(max(0.0, (time.perf_counter() - float(started_at))) * 1000.0)
    payload = {
        "task_name": task_name,
        "status": status,
        "duration_ms": duration_ms,
        "trace_id": str(trace_id or ""),
        "timestamp": datetime.utcnow().isoformat(),
    }
    payload.update(extra or {})
    try:
        current_app.logger.info(json.dumps(payload))
    except Exception:
        pass


@shared_task(bind=True, name="app.tasks.search_tasks.search_index_listing", max_retries=5)
def search_index_listing(self, listing_id: int, trace_id: str = ""):
    started = time.perf_counter()
    if not search_engine_is_meili():
        return {"ok": True, "skipped": "search_engine_not_meili"}
    try:
        listing = Listing.query.get(int(listing_id))
        client = get_meili_client()
        index_name = listings_index_name()
        if listing is None:
            client.delete_document(index_name, int(listing_id))
            _task_log("search_index_listing", status="deleted_missing", started_at=started, trace_id=trace_id, listing_id=int(listing_id))
            return {"ok": True, "deleted": True, "listing_id": int(listing_id)}
        if not listing_should_be_indexed(listing):
            client.delete_document(index_name, int(listing_id))
            _task_log("search_index_listing", status="deleted_unsearchable", started_at=started, trace_id=trace_id, listing_id=int(listing_id))
            return {"ok": True, "deleted": True, "listing_id": int(listing_id)}
        doc = listing_to_search_document(listing)
        client.upsert_documents(index_name, [doc])
        _task_log("search_index_listing", status="indexed", started_at=started, trace_id=trace_id, listing_id=int(listing_id))
        return {"ok": True, "indexed": True, "listing_id": int(listing_id)}
    except SearchUnavailable as exc:
        if int(self.request.retries or 0) < int(self.max_retries or 0):
            countdown = _retry_countdown(int(self.request.retries or 0))
            _task_log(
                "search_index_listing",
                status="retrying",
                started_at=started,
                trace_id=trace_id,
                listing_id=int(listing_id),
                countdown=countdown,
                detail=str(exc),
            )
            raise self.retry(exc=exc, countdown=countdown)
        _task_log("search_index_listing", status="failed", started_at=started, trace_id=trace_id, listing_id=int(listing_id), detail=str(exc))
        raise


@shared_task(bind=True, name="app.tasks.search_tasks.search_delete_listing", max_retries=5)
def search_delete_listing(self, listing_id: int, trace_id: str = ""):
    started = time.perf_counter()
    if not search_engine_is_meili():
        return {"ok": True, "skipped": "search_engine_not_meili"}
    try:
        client = get_meili_client()
        client.delete_document(listings_index_name(), int(listing_id))
        _task_log("search_delete_listing", status="deleted", started_at=started, trace_id=trace_id, listing_id=int(listing_id))
        return {"ok": True, "deleted": True, "listing_id": int(listing_id)}
    except SearchUnavailable as exc:
        if int(self.request.retries or 0) < int(self.max_retries or 0):
            countdown = _retry_countdown(int(self.request.retries or 0))
            _task_log(
                "search_delete_listing",
                status="retrying",
                started_at=started,
                trace_id=trace_id,
                listing_id=int(listing_id),
                countdown=countdown,
                detail=str(exc),
            )
            raise self.retry(exc=exc, countdown=countdown)
        _task_log("search_delete_listing", status="failed", started_at=started, trace_id=trace_id, listing_id=int(listing_id), detail=str(exc))
        raise


@shared_task(bind=True, name="app.tasks.search_tasks.search_reindex_all", max_retries=5)
def search_reindex_all(self, batch_size: int = 500, since_id: int | None = None, trace_id: str = ""):
    started = time.perf_counter()
    if not search_engine_is_meili():
        return {"ok": True, "skipped": "search_engine_not_meili"}
    try:
        safe_batch = max(1, min(int(batch_size or 500), 2000))
        last_seen_id = int(since_id or 0)
        indexed = 0
        deleted = 0
        scanned = 0
        client = get_meili_client()
        index_name = listings_index_name()
        while True:
            rows = (
                Listing.query
                .filter(Listing.id > int(last_seen_id))
                .order_by(Listing.id.asc())
                .limit(int(safe_batch))
                .all()
            )
            if not rows:
                break
            docs: list[dict] = []
            delete_ids: list[int] = []
            for row in rows:
                scanned += 1
                last_seen_id = int(row.id)
                if listing_should_be_indexed(row):
                    docs.append(listing_to_search_document(row))
                else:
                    delete_ids.append(int(row.id))
            if docs:
                client.upsert_documents(index_name, docs)
                indexed += len(docs)
            for delete_id in delete_ids:
                client.delete_document(index_name, int(delete_id))
                deleted += 1
        _task_log(
            "search_reindex_all",
            status="ok",
            started_at=started,
            trace_id=trace_id,
            scanned=int(scanned),
            indexed=int(indexed),
            deleted=int(deleted),
            since_id=int(since_id or 0),
            last_seen_id=int(last_seen_id),
        )
        return {
            "ok": True,
            "scanned": int(scanned),
            "indexed": int(indexed),
            "deleted": int(deleted),
            "last_seen_id": int(last_seen_id),
        }
    except SearchUnavailable as exc:
        if int(self.request.retries or 0) < int(self.max_retries or 0):
            countdown = _retry_countdown(int(self.request.retries or 0))
            _task_log(
                "search_reindex_all",
                status="retrying",
                started_at=started,
                trace_id=trace_id,
                countdown=countdown,
                detail=str(exc),
            )
            raise self.retry(exc=exc, countdown=countdown)
        _task_log("search_reindex_all", status="failed", started_at=started, trace_id=trace_id, detail=str(exc))
        raise
