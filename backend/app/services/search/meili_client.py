from __future__ import annotations

import os
from typing import Any

import requests


class SearchUnavailable(RuntimeError):
    """Raised when the configured search engine is unavailable."""


def _timeout_seconds() -> float:
    raw = (os.getenv("SEARCH_TIMEOUT_MS") or "1500").strip()
    try:
        timeout_ms = int(raw)
    except Exception:
        timeout_ms = 1500
    if timeout_ms < 100:
        timeout_ms = 100
    return float(timeout_ms) / 1000.0


class MeiliClient:
    def __init__(self, *, host: str | None = None, api_key: str | None = None, timeout: float | None = None):
        resolved_host = str(host or os.getenv("MEILI_HOST") or "").strip()
        if not resolved_host:
            raise SearchUnavailable("MEILI_HOST is not configured")
        self.host = resolved_host.rstrip("/")
        self.api_key = str(api_key if api_key is not None else (os.getenv("MEILI_API_KEY") or "")).strip()
        self.timeout = float(timeout if timeout is not None else _timeout_seconds())
        self.session = requests.Session()
        if self.api_key:
            self.session.headers.update({"Authorization": f"Bearer {self.api_key}"})
        self.session.headers.update({"Content-Type": "application/json"})

    def _request(self, method: str, path: str, *, json_body: dict | list | None = None, ok_codes: tuple[int, ...] = (200, 201, 202, 204)) -> Any:
        url = f"{self.host}{path}"
        try:
            response = self.session.request(method=method, url=url, json=json_body, timeout=self.timeout)
        except requests.Timeout as exc:
            raise SearchUnavailable("Meilisearch request timed out") from exc
        except requests.RequestException as exc:
            raise SearchUnavailable(f"Meilisearch request failed: {exc}") from exc

        if int(response.status_code) not in ok_codes:
            if int(response.status_code) in (500, 502, 503, 504):
                raise SearchUnavailable(f"Meilisearch unavailable ({response.status_code})")
            try:
                detail = response.json()
            except Exception:
                detail = {"message": response.text[:300]}
            raise SearchUnavailable(f"Meilisearch error {response.status_code}: {detail}")

        if int(response.status_code) == 204:
            return {}
        try:
            return response.json()
        except Exception:
            return {}

    def healthcheck(self) -> dict[str, Any]:
        return self._request("GET", "/health", ok_codes=(200,))

    def ensure_index(self, index_name: str) -> dict[str, Any]:
        safe_name = str(index_name or "").strip()
        if not safe_name:
            raise SearchUnavailable("Index name is required")
        try:
            return self._request("GET", f"/indexes/{safe_name}", ok_codes=(200,))
        except SearchUnavailable:
            payload = {"uid": safe_name, "primaryKey": "id"}
            try:
                self._request("POST", "/indexes", json_body=payload, ok_codes=(200, 201, 202))
            except SearchUnavailable:
                # Might already exist under race conditions.
                pass
            return self._request("GET", f"/indexes/{safe_name}", ok_codes=(200,))

    def configure_listings_index(self, index_name: str) -> dict[str, Any]:
        safe_name = str(index_name or "").strip()
        self.ensure_index(safe_name)
        payload = {
            "filterableAttributes": [
                "state",
                "state_ci",
                "city",
                "city_ci",
                "locality_ci",
                "category",
                "category_ci",
                "category_id",
                "brand_id",
                "model_id",
                "listing_type",
                "approval_status",
                "is_active",
                "merchant_id",
                "delivery_available",
                "inspection_required",
                "furnished",
                "serviced",
                "property_type",
                "property_type_ci",
                "make",
                "make_ci",
                "model",
                "model_ci",
                "year",
                "battery_type_ci",
                "inverter_capacity_ci",
                "lithium_only",
                "bedrooms",
                "bathrooms",
                "land_size",
                "title_document_type_ci",
                "condition_ci",
                "status_ci",
            ],
            "sortableAttributes": [
                "price",
                "final_price",
                "created_at",
                "heat_score",
                "ranking_score",
                "price_minor",
                "final_price_minor",
                "year",
            ],
            "searchableAttributes": [
                "title",
                "description",
                "city",
                "state",
                "make",
                "model",
                "property_type",
                "category",
                "battery_type",
                "inverter_capacity",
            ],
        }
        return self._request("PATCH", f"/indexes/{safe_name}/settings", json_body=payload, ok_codes=(200, 202))

    def upsert_documents(self, index_name: str, docs: list[dict[str, Any]]) -> dict[str, Any]:
        safe_name = str(index_name or "").strip()
        if not docs:
            return {"ok": True, "queued": False}
        self.ensure_index(safe_name)
        return self._request(
            "POST",
            f"/indexes/{safe_name}/documents?primaryKey=id",
            json_body=docs,
            ok_codes=(200, 202),
        )

    def delete_document(self, index_name: str, doc_id: int | str) -> dict[str, Any]:
        safe_name = str(index_name or "").strip()
        self.ensure_index(safe_name)
        return self._request(
            "DELETE",
            f"/indexes/{safe_name}/documents/{doc_id}",
            ok_codes=(200, 202, 204),
        )

    def search(
        self,
        index_name: str,
        q: str,
        filters: str | None,
        sort: list[str] | None,
        limit: int,
        offset: int,
    ) -> dict[str, Any]:
        safe_name = str(index_name or "").strip()
        self.ensure_index(safe_name)
        payload: dict[str, Any] = {
            "q": str(q or ""),
            "limit": int(max(1, limit)),
            "offset": int(max(0, offset)),
        }
        if filters:
            payload["filter"] = filters
        if sort:
            payload["sort"] = list(sort)
        return self._request(
            "POST",
            f"/indexes/{safe_name}/search",
            json_body=payload,
            ok_codes=(200,),
        )


def get_meili_client() -> MeiliClient:
    return MeiliClient()
