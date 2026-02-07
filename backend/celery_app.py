import os

from celery import Celery

from app import create_app


def _resolve_broker_url() -> str:
    return (os.getenv("REDIS_URL") or os.getenv("CELERY_BROKER_URL") or "").strip()


def _resolve_backend_url(broker_url: str) -> str:
    return (os.getenv("REDIS_URL") or os.getenv("CELERY_RESULT_BACKEND") or broker_url or "").strip()


flask_app = create_app()
_broker_url = _resolve_broker_url()
_backend_url = _resolve_backend_url(_broker_url)

if not _broker_url:
    _broker_url = "redis://localhost:6379/0"
if not _backend_url:
    _backend_url = _broker_url

celery = Celery("fliptrybe", broker=_broker_url, backend=_backend_url)
celery.conf.update(flask_app.config)


class ContextTask(celery.Task):
    def __call__(self, *args, **kwargs):
        with flask_app.app_context():
            return self.run(*args, **kwargs)


celery.Task = ContextTask
