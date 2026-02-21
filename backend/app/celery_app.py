from __future__ import annotations

import json
import os
from datetime import datetime

from celery import Celery
from celery.signals import task_failure, task_retry


_SIGNALS_BOUND = False


def _broker_url() -> str:
    return (
        (os.getenv("CELERY_BROKER_URL") or "").strip()
        or (os.getenv("REDIS_URL") or "").strip()
        or "redis://localhost:6379/0"
    )


def _result_backend(broker_url: str) -> str:
    return (
        (os.getenv("CELERY_RESULT_BACKEND") or "").strip()
        or (os.getenv("REDIS_URL") or "").strip()
        or broker_url
    )


def _escrow_interval_seconds() -> int:
    raw = (os.getenv("ESCROW_SETTLEMENT_INTERVAL_SECONDS") or "300").strip()
    try:
        value = int(raw)
    except Exception:
        value = 300
    if value < 30:
        value = 30
    return value


def _extract_trace_id(args, kwargs) -> str:
    try:
        if isinstance(kwargs, dict):
            trace_id = str(kwargs.get("trace_id") or "").strip()
            if trace_id:
                return trace_id
        if isinstance(args, (list, tuple)):
            for item in args:
                if isinstance(item, str) and item.strip().startswith("trace_"):
                    return item.strip()
    except Exception:
        pass
    return ""


def _bind_task_observers(flask_app) -> None:
    global _SIGNALS_BOUND
    if _SIGNALS_BOUND:
        return

    @task_failure.connect(weak=False)
    def _on_task_failure(sender=None, task_id=None, exception=None, args=None, kwargs=None, einfo=None, **extra):
        payload = {
            "event": "celery_task_failure",
            "task_name": getattr(sender, "name", "") if sender is not None else "",
            "task_id": str(task_id or ""),
            "trace_id": _extract_trace_id(args, kwargs),
            "exception": str(exception or ""),
            "retry_count": int(extra.get("retries", 0) or 0),
            "timestamp": datetime.utcnow().isoformat(),
        }
        if einfo is not None:
            payload["einfo"] = str(einfo)
        try:
            flask_app.logger.error(json.dumps(payload))
        except Exception:
            pass

    @task_retry.connect(weak=False)
    def _on_task_retry(request=None, reason=None, einfo=None, **extra):
        kwargs = getattr(request, "kwargs", None)
        args = getattr(request, "args", None)
        payload = {
            "event": "celery_task_retry",
            "task_name": str(getattr(request, "task", "") or ""),
            "task_id": str(getattr(request, "id", "") or ""),
            "trace_id": _extract_trace_id(args, kwargs),
            "reason": str(reason or ""),
            "retry_count": int(getattr(request, "retries", 0) or 0),
            "timestamp": datetime.utcnow().isoformat(),
        }
        if einfo is not None:
            payload["einfo"] = str(einfo)
        try:
            flask_app.logger.warning(json.dumps(payload))
        except Exception:
            pass

    _SIGNALS_BOUND = True


def create_celery_app(flask_app) -> Celery:
    broker = _broker_url()
    backend = _result_backend(broker)
    celery = Celery(flask_app.import_name, broker=broker, backend=backend)
    celery.conf.update(
        task_serializer="json",
        accept_content=["json"],
        result_serializer="json",
        task_track_started=True,
        task_acks_late=True,
        worker_prefetch_multiplier=1,
        broker_connection_retry_on_startup=True,
        timezone="UTC",
        enable_utc=True,
        beat_schedule={
            "escrow-settlement-runner": {
                "task": "app.tasks.scale_tasks.run_escrow_settlement",
                "schedule": float(_escrow_interval_seconds()),
            },
        },
    )
    celery.conf.update(flask_app.config)

    class FlaskContextTask(celery.Task):
        def __call__(self, *args, **kwargs):
            with flask_app.app_context():
                return self.run(*args, **kwargs)

    celery.Task = FlaskContextTask
    celery.autodiscover_tasks(["app.tasks"])
    _bind_task_observers(flask_app)
    return celery
