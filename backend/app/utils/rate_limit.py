from __future__ import annotations

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
