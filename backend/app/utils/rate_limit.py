from __future__ import annotations

import os
import threading
import time


_LOCK = threading.Lock()
_WINDOWS: dict[str, list[float]] = {}


def check_limit(key: str, *, limit: int, window_seconds: int) -> tuple[bool, int]:
    now = time.time()
    start = now - max(1, int(window_seconds))
    safe_limit = max(1, int(limit))
    with _LOCK:
        bucket = _WINDOWS.get(key, [])
        bucket = [ts for ts in bucket if ts >= start]
        if len(bucket) >= safe_limit:
            retry_after = int(max(1, window_seconds - (now - min(bucket))))
            _WINDOWS[key] = bucket
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
    return _env_bool("RATE_LIMIT_ENABLED", default)


def rate_limit_burst(default: int) -> int:
    return _env_int("RATE_LIMIT_BURST", default, minimum=1, maximum=10000)


def rate_limit_window_sec(default: int) -> int:
    return _env_int("RATE_LIMIT_WINDOW_SEC", default, minimum=1, maximum=86400)


def trust_proxy_headers(default: bool = True) -> bool:
    return _env_bool("TRUST_PROXY_HEADERS", default)


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
