from __future__ import annotations

import os
import threading
import time
from functools import wraps

from flask import jsonify, request, g

try:
    import redis
except Exception:  # pragma: no cover - optional dependency fallback
    redis = None


_LOCK = threading.Lock()
_WINDOWS: dict[str, list[float]] = {}
_CLIENT = None
_CLIENT_INIT = False
_STATS = {
    "redis_hits": 0,
    "redis_errors": 0,
    "memory_hits": 0,
}


def check_limit(key: str, *, limit: int, window_seconds: int) -> tuple[bool, int]:
    safe_window = max(1, int(window_seconds))
    safe_limit = max(1, int(limit))
    redis_client = _get_client()
    if redis_client is not None:
        now_sec = int(time.time())
        window_epoch = now_sec // safe_window
        counter_key = f"rl:v1:{key}:{window_epoch}"
        try:
            current = int(redis_client.incr(counter_key))
            if current == 1:
                redis_client.expire(counter_key, safe_window + 1)
            with _LOCK:
                _STATS["redis_hits"] = int(_STATS.get("redis_hits", 0) or 0) + 1
            if current <= safe_limit:
                return True, 0
            retry_after = int(max(1, safe_window - (now_sec % safe_window)))
            return False, retry_after
        except Exception:
            with _LOCK:
                _STATS["redis_errors"] = int(_STATS.get("redis_errors", 0) or 0) + 1
    return _check_limit_memory(key, limit=safe_limit, window_seconds=safe_window)


def _check_limit_memory(key: str, *, limit: int, window_seconds: int) -> tuple[bool, int]:
    now = time.time()
    start = now - max(1, int(window_seconds))
    safe_limit = max(1, int(limit))
    with _LOCK:
        bucket = _WINDOWS.get(key, [])
        bucket = [ts for ts in bucket if ts >= start]
        if len(bucket) >= safe_limit:
            retry_after = int(max(1, window_seconds - (now - min(bucket))))
            _WINDOWS[key] = bucket
            _STATS["memory_hits"] = int(_STATS.get("memory_hits", 0) or 0) + 1
            return False, retry_after
        bucket.append(now)
        _WINDOWS[key] = bucket
    return True, 0


def _env_bool(name: str, default: bool) -> bool:
    raw = (os.getenv(name) or "").strip().lower()
    if not raw:
        return bool(default)
    return raw in ("1", "true", "yes", "on")


def _env_int(name: str, default: int, *, minimum: int = 1, maximum: int | None = None) -> int:
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
    if maximum is not None and value > maximum:
        value = maximum
    return value


def rate_limit_enabled(default: bool = True) -> bool:
    if (os.getenv("ENABLE_RATE_LIMIT") or "").strip():
        return _env_bool("ENABLE_RATE_LIMIT", default)
    return _env_bool("RATE_LIMIT_ENABLED", default)


def _rate_limit_burst_value(default: int) -> int:
    return _env_int("RATE_LIMIT_BURST", default, minimum=1, maximum=10000)


def rate_limit_window_sec(default: int) -> int:
    return _env_int("RATE_LIMIT_WINDOW_SEC", default, minimum=1, maximum=86400)


def trust_proxy_headers(default: bool = False) -> bool:
    return _env_bool("TRUST_PROXY_HEADERS", default)


def _rate_limit_redis_url() -> str:
    return (os.getenv("RATE_LIMIT_REDIS_URL") or os.getenv("REDIS_URL") or "").strip()


def _get_client():
    global _CLIENT, _CLIENT_INIT
    if not rate_limit_enabled(True):
        return None
    with _LOCK:
        if _CLIENT_INIT:
            return _CLIENT
        _CLIENT_INIT = True
    if redis is None:
        return None
    url = _rate_limit_redis_url()
    if not url:
        return None
    try:
        client = redis.Redis.from_url(
            url,
            decode_responses=True,
            socket_connect_timeout=0.75,
            socket_timeout=0.75,
            health_check_interval=30,
        )
        client.ping()
        with _LOCK:
            _CLIENT = client
        return client
    except Exception:
        with _LOCK:
            _CLIENT = None
        return None


def resolve_client_ip(request, *, trusted_proxy: bool = True) -> str:
    if trusted_proxy:
        xff = (request.headers.get("X-Forwarded-For") or "").strip()
        if xff:
            first_hop = (xff.split(",")[0] or "").strip()
            if first_hop:
                return first_hop
        x_real_ip = (request.headers.get("X-Real-IP") or "").strip()
        if x_real_ip:
            return x_real_ip
    remote = (request.remote_addr or "").strip()
    if remote:
        return remote
    return "unknown"


def rate_limit(
    key: str,
    per_seconds: int,
    limit: int,
    *,
    scope: str = "ip",
    trusted_proxy: bool | None = None,
    message: str = "Too many requests. Please retry later.",
):
    """
    Flask decorator wrapper over check_limit.
    """
    safe_key = str(key or "rate_limit")
    safe_window = max(1, int(per_seconds or 1))
    safe_limit = max(1, int(limit or 1))
    trusted = trust_proxy_headers(False) if trusted_proxy is None else bool(trusted_proxy)

    def decorator(fn):
        @wraps(fn)
        def wrapped(*args, **kwargs):
            scope_key = safe_key
            normalized_scope = (scope or "ip").strip().lower()
            if normalized_scope == "user":
                user_id = getattr(g, "auth_user_id", None)
                if user_id is not None:
                    scope_key = f"{scope_key}:u:{int(user_id)}"
            else:
                scope_key = f"{scope_key}:ip:{resolve_client_ip(request, trusted_proxy=trusted)}"

            ok, retry_after = check_limit(scope_key, limit=safe_limit, window_seconds=safe_window)
            if ok:
                return fn(*args, **kwargs)
            return (
                jsonify(
                    {
                        "ok": False,
                        "error": "RATE_LIMITED",
                        "message": message,
                        "retry_after": int(retry_after or 0),
                    }
                ),
                429,
            )

        return wrapped

    return decorator


def limiter_stats() -> dict:
    with _LOCK:
        return {
            "enabled": bool(rate_limit_enabled(True)),
            "redis_configured": bool(_rate_limit_redis_url()),
            "redis_connected": bool(_CLIENT is not None),
            "redis_hits": int(_STATS.get("redis_hits", 0) or 0),
            "redis_errors": int(_STATS.get("redis_errors", 0) or 0),
            "memory_hits": int(_STATS.get("memory_hits", 0) or 0),
        }


def build_rate_limit_subject(*, scope: str, user_id: int | None, request_obj=None, trusted_proxy: bool | None = None) -> str:
    req = request_obj or request
    normalized_scope = (scope or "ip").strip().lower()
    trusted = trust_proxy_headers(False) if trusted_proxy is None else bool(trusted_proxy)
    if normalized_scope == "user" and user_id is not None:
        return f"u:{int(user_id)}"
    return f"ip:{resolve_client_ip(req, trusted_proxy=trusted)}"


def rate_limit_burst(
    default_or_key,
    per_seconds: int | None = None,
    burst: int | None = None,
    *,
    scope: str = "ip",
    trusted_proxy: bool | None = None,
    message: str = "Too many requests. Please retry later.",
):
    """
    Backward-compatible helper:
    - `rate_limit_burst(default_int)` -> configured burst integer.
    - `rate_limit_burst(key, per_seconds, burst, ...)` -> rate limit decorator.
    """
    if (
        isinstance(default_or_key, int)
        and per_seconds is None
        and burst is None
    ):
        return _rate_limit_burst_value(int(default_or_key))

    if per_seconds is None:
        raise TypeError("rate_limit_burst decorator mode requires per_seconds")
    if burst is None:
        raise TypeError("rate_limit_burst decorator mode requires burst")

    configured_burst = _rate_limit_burst_value(int(burst))
    return rate_limit(
        str(default_or_key),
        int(per_seconds),
        int(configured_burst),
        scope=scope,
        trusted_proxy=trusted_proxy,
        message=message,
    )


__all__ = [
    "check_limit",
    "rate_limit",
    "rate_limit_burst",
    "rate_limit_enabled",
    "rate_limit_window_sec",
    "resolve_client_ip",
    "trust_proxy_headers",
    "limiter_stats",
    "build_rate_limit_subject",
]
