from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def main() -> int:
    try:
        from celery_app import celery

        # Access one config value to ensure the app object is initialized.
        _ = str(celery.conf.broker_url or "")
        print("ok: celery_app:celery import succeeded")
        return 0
    except Exception as exc:
        print(f"error: failed to import celery_app:celery -> {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
