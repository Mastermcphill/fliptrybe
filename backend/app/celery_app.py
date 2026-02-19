from __future__ import annotations

import os

from celery import Celery


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
    return celery
