from __future__ import annotations

import hashlib
import json
import os
import threading
from typing import Any

try:
    import redis
except Exception:  # pragma: no cover - optional dependency safety
    redis = None


_LOCK = threading.Lock()
_CLIENT = None
_CLIENT_INIT_ATTEMPTED = False

_STATS = {
    "hits": 0,
    "misses": 0,
    "sets": 0,
    "deletes": 0,
    "errors": 0,
}


def _env_bool(name: str, default: bool) -> bool:
    raw = (os.getenv(name) or "").strip().lower()
    if not raw:
        return bool(default)
    return raw in ("1", "true", "yes", "on")


def _env_int(name: str, default: int, *, minimum: int = 1, maximum: int = 86400) -> int:
    raw = (os.getenv(name) or "").strip()
    if not raw:
        value = int(default)
    else:
        try:
            value = int(raw)
        except Exception:
            value = int(default)
    if value < minimum:
        value = minimum
    if value > maximum:
        value = maximum
    return value


def cache_enabled(default: bool = False) -> bool:
    return _env_bool("ENABLE_CACHE", default)


def cache_ttl_seconds(env_name: str, default: int) -> int:
    return _env_int(env_name, default, minimum=1, maximum=86400)


def default_cache_ttl_seconds() -> int:
    return cache_ttl_seconds("DEFAULT_CACHE_TTL_SECONDS", 60)


def listing_detail_cache_ttl_seconds() -> int:
    return cache_ttl_seconds("LISTING_DETAIL_CACHE_TTL_SECONDS", 300)


def feed_cache_ttl_seconds() -> int:
    return cache_ttl_seconds("FEED_CACHE_TTL_SECONDS", 30)


def _cache_redis_url() -> str:
    return (os.getenv("CACHE_REDIS_URL") or os.getenv("REDIS_URL") or "").strip()


def _bump_stat(name: str, delta: int = 1) -> None:
    with _LOCK:
        _STATS[name] = int(_STATS.get(name, 0) or 0) + int(delta)


def _get_client():
    global _CLIENT, _CLIENT_INIT_ATTEMPTED
    if not cache_enabled(False):
        return None
    with _LOCK:
        if _CLIENT_INIT_ATTEMPTED:
            return _CLIENT
        _CLIENT_INIT_ATTEMPTED = True

    if redis is None:
        _bump_stat("errors")
        return None
    url = _cache_redis_url()
    if not url:
        return None
    try:
        client = redis.Redis.from_url(
            url,
            decode_responses=True,
            socket_timeout=0.75,
            socket_connect_timeout=0.75,
            health_check_interval=30,
        )
        client.ping()
        with _LOCK:
            _CLIENT = client
        return client
    except Exception:
        _bump_stat("errors")
        with _LOCK:
            _CLIENT = None
        return None


def _stable_param_value(value: Any) -> str:
    if isinstance(value, (dict, list, tuple)):
        try:
            return json.dumps(value, sort_keys=True, separators=(",", ":"), default=str)
        except Exception:
            return str(value)
    if value is None:
        return ""
    return str(value)


def build_cache_key(scope: str, params: dict[str, Any] | None = None) -> str:
    safe_scope = str(scope or "default").strip().lower().replace(" ", "_")
    payload = params or {}
    parts: list[str] = []
    for key in sorted(payload.keys()):
        parts.append(f"{str(key)}={_stable_param_value(payload.get(key))}")
    joined = "&".join(parts)
    if len(joined) > 420:
        joined = hashlib.sha256(joined.encode("utf-8")).hexdigest()
    return f"v1:{safe_scope}:{joined}"


def get_json(key: str) -> dict | list | None:
    client = _get_client()
    if client is None:
        return None
    try:
        raw = client.get(str(key))
        if not raw:
            _bump_stat("misses")
            return None
        parsed = json.loads(raw)
        _bump_stat("hits")
        return parsed
    except Exception:
        _bump_stat("errors")
        return None


def set_json(key: str, value: Any, ttl_seconds: int | None = None) -> bool:
    client = _get_client()
    if client is None:
        return False
    ttl = int(ttl_seconds or default_cache_ttl_seconds())
    if ttl <= 0:
        ttl = default_cache_ttl_seconds()
    try:
        payload = json.dumps(value, separators=(",", ":"), default=str)
        client.setex(str(key), ttl, payload)
        _bump_stat("sets")
        return True
    except Exception:
        _bump_stat("errors")
        return False


def delete(key: str) -> int:
    client = _get_client()
    if client is None:
        return 0
    try:
        removed = int(client.delete(str(key)) or 0)
        if removed > 0:
            _bump_stat("deletes", removed)
        return removed
    except Exception:
        _bump_stat("errors")
        return 0


def delete_prefix(prefix: str, *, scan_count: int = 200) -> int:
    client = _get_client()
    if client is None:
        return 0
    pattern = f"{str(prefix)}*"
    total = 0
    try:
        cursor = 0
        while True:
            cursor, keys = client.scan(cursor=cursor, match=pattern, count=int(scan_count))
            if keys:
                total += int(client.delete(*keys) or 0)
            if cursor == 0:
                break
        if total > 0:
            _bump_stat("deletes", total)
        return int(total)
    except Exception:
        _bump_stat("errors")
        return int(total)


def cache_stats() -> dict:
    client = _get_client()
    base = {
        "enabled": bool(cache_enabled(False) and client is not None),
        "url_configured": bool(_cache_redis_url()),
    }
    with _LOCK:
        base.update(
            {
                "hits": int(_STATS.get("hits", 0) or 0),
                "misses": int(_STATS.get("misses", 0) or 0),
                "sets": int(_STATS.get("sets", 0) or 0),
                "deletes": int(_STATS.get("deletes", 0) or 0),
                "errors": int(_STATS.get("errors", 0) or 0),
            }
        )
    return base


def _reset_cache_state_for_tests() -> None:
    global _CLIENT, _CLIENT_INIT_ATTEMPTED
    with _LOCK:
        _CLIENT = None
        _CLIENT_INIT_ATTEMPTED = False
        for key in _STATS:
            _STATS[key] = 0

