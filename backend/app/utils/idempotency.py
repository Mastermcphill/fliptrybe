from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime
from typing import Any

from flask import has_request_context, request

from app.extensions import db
from app.models import IdempotencyKey


def _env_bool(name: str, default: bool) -> bool:
    raw = (os.getenv(name) or "").strip().lower()
    if not raw:
        return bool(default)
    return raw in ("1", "true", "yes", "on")


def idempotency_enforced() -> bool:
    return _env_bool("ENABLE_IDEMPOTENCY_ENFORCEMENT", False)


def _canonical_json(payload: Any) -> str:
    try:
        return json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
    except Exception:
        return str(payload)


def _request_method() -> str:
    if has_request_context():
        return str(request.method or "").strip().upper() or "POST"
    return "POST"


def _request_path(default_path: str = "") -> str:
    if has_request_context():
        return str(request.path or "").strip() or default_path
    return default_path


def _hash_request(*, method: str, path: str, payload: Any) -> str:
    canonical = _canonical_json(payload)
    raw = f"{method.strip().upper()}|{path.strip()}|{canonical}".encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _normalize_scope(scope: str | None, route: str | None) -> str:
    if scope:
        return str(scope).strip()
    if route:
        return str(route).strip()
    return _request_path("")


def _required_scope_prefixes() -> list[str]:
    raw = (os.getenv("IDEMPOTENCY_REQUIRED_SCOPES") or "").strip()
    if raw:
        out = [s.strip() for s in raw.split(",") if s.strip()]
        if out:
            return out
    return [
        "/api/orders",
        "/api/payments/initialize",
        "/api/payments/webhook/paystack",
        "/api/webhooks/paystack",
        "/api/wallet/payouts",
        "webhook:paystack",
        "wallet",
        "escrow",
    ]


def _scope_requires_header(scope: str) -> bool:
    normalized = str(scope or "").strip()
    if not normalized:
        return False
    for prefix in _required_scope_prefixes():
        if normalized.startswith(prefix):
            return True
    return False


def get_idempotency_key() -> str | None:
    # Common header pattern
    if not has_request_context():
        return None
    k = request.headers.get("Idempotency-Key") or request.headers.get("X-Idempotency-Key")
    if not k:
        return None
    return k.strip()[:128]


def _required_key_response(scope: str) -> tuple[str, dict, int]:
    return (
        "required",
        {
            "ok": False,
            "error": {
                "code": "IDEMPOTENCY_KEY_REQUIRED",
                "message": f"Idempotency-Key header is required for {scope or 'this operation'}.",
            },
        },
        400,
    )


def _reuse_conflict_response() -> tuple[str, dict, int]:
    return (
        "conflict",
        {
            "ok": False,
            "error": {
                "code": "IDEMPOTENCY_KEY_REUSE",
                "message": "This Idempotency-Key was already used with a different request payload.",
            },
        },
        409,
    )


def lookup_response(
    user_id: int | None,
    route: str,
    payload: Any,
    *,
    scope: str | None = None,
    idempotency_key: str | None = None,
    require_header: bool | None = None,
):
    scope_key = _normalize_scope(scope, route)
    k = (idempotency_key or get_idempotency_key() or "").strip()[:128]
    should_require = bool(require_header) if require_header is not None else (
        bool(idempotency_enforced() and _scope_requires_header(scope_key))
    )
    if not k:
        if should_require:
            return _required_key_response(scope_key)
        return None

    req_hash = _hash_request(
        method=_request_method(),
        path=_request_path(scope_key or route),
        payload=payload,
    )
    row = (
        IdempotencyKey.query
        .filter_by(scope=scope_key, key=k)
        .order_by(IdempotencyKey.id.asc())
        .first()
    )
    if row is None:
        # Backward compatibility with legacy rows saved without scope.
        row = (
            IdempotencyKey.query
            .filter_by(key=k)
            .order_by(IdempotencyKey.id.asc())
            .first()
        )
    if row:
        # If same key but different payload, treat as conflict.
        if (row.request_hash or "").strip() and str(row.request_hash).strip() != req_hash:
            return _reuse_conflict_response()
        if row.response_body_json or row.response_json:
            try:
                raw_body = row.response_body_json or row.response_json
                return ("hit", json.loads(raw_body), int(row.response_code or row.status_code or 200))
            except Exception:
                return ("hit", {"ok": True}, int(row.response_code or row.status_code or 200))
        return ("hit", {"ok": True}, int(row.response_code or row.status_code or 200))

    row = IdempotencyKey(
        key=k,
        scope=scope_key,
        user_id=int(user_id) if user_id is not None else None,
        route=str(route or ""),
        request_hash=req_hash,
        response_json=None,
        response_body_json=None,
        status_code=200,
        response_code=200,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    db.session.add(row)
    db.session.commit()
    return ("miss", row, 0)


def store_response(row: IdempotencyKey, response_json: Any, status_code: int):
    try:
        encoded = json.dumps(response_json, separators=(",", ":"), default=str)
        row.response_json = encoded
        row.response_body_json = encoded
    except Exception:
        fallback = json.dumps({"ok": True})
        row.response_json = fallback
        row.response_body_json = fallback
    row.status_code = int(status_code or 200)
    row.response_code = int(status_code or 200)
    row.updated_at = datetime.utcnow()
    db.session.add(row)
    db.session.commit()
