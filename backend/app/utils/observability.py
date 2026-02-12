from __future__ import annotations

import hashlib
import json
import os
import time
import uuid
from datetime import datetime

from flask import g, request


def _hash_ip(ip: str, salt: str) -> str:
    raw = f"{salt}:{ip or ''}".encode("utf-8")
    return hashlib.sha256(raw).hexdigest()[:16]


def get_request_id() -> str:
    return getattr(g, "request_id", "")


def init_sentry(app) -> None:
    dsn = (os.getenv("SENTRY_DSN") or "").strip()
    if not dsn:
        app.logger.info("sentry_disabled_no_dsn")
        return
    try:
        import sentry_sdk
        from sentry_sdk.integrations.flask import FlaskIntegration

        traces_rate_raw = (os.getenv("SENTRY_TRACES_SAMPLE_RATE") or "0.0").strip()
        try:
            traces_rate = float(traces_rate_raw)
        except Exception:
            traces_rate = 0.0

        sentry_sdk.init(
            dsn=dsn,
            environment=(os.getenv("SENTRY_ENVIRONMENT") or os.getenv("FLIPTRYBE_ENV") or "dev"),
            release=(os.getenv("GIT_SHA") or os.getenv("RENDER_GIT_COMMIT") or "unknown"),
            integrations=[FlaskIntegration()],
            send_default_pii=False,
            traces_sample_rate=max(0.0, min(traces_rate, 1.0)),
            before_send=_before_send_scrub,
        )
        app.logger.info("sentry_enabled")
    except Exception as e:
        app.logger.warning("sentry_init_failed err=%s", e)


def _before_send_scrub(event, hint):
    try:
        req = event.get("request") or {}
        headers = req.get("headers") or {}
        for key in list(headers.keys()):
            kl = key.lower()
            if kl in ("authorization", "x-api-key", "cookie", "set-cookie"):
                headers[key] = "[REDACTED]"
        req["headers"] = headers
        event["request"] = req
    except Exception:
        pass
    return event


def init_otel(app, *, enabled: bool) -> None:
    if not enabled:
        return
    try:
        endpoint = (os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT") or "").strip()
        if not endpoint:
            app.logger.info("otel_disabled_no_endpoint")
            return
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
        from opentelemetry.instrumentation.flask import FlaskInstrumentor
        from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor

        resource = Resource.create({"service.name": "fliptrybe-backend"})
        provider = TracerProvider(resource=resource)
        processor = BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint))
        provider.add_span_processor(processor)
        trace.set_tracer_provider(provider)
        FlaskInstrumentor().instrument_app(app)
        try:
            from app.extensions import db

            SQLAlchemyInstrumentor().instrument(engine=db.engine)
        except Exception:
            pass
        app.logger.info("otel_enabled")
    except Exception as e:
        app.logger.warning("otel_init_failed err=%s", e)


def install_request_observers(app) -> None:
    @app.before_request
    def _request_observer_begin():
        rid = (request.headers.get("X-Request-Id") or "").strip()
        if not rid:
            rid = uuid.uuid4().hex
        g.request_id = rid
        g.request_started_at = time.perf_counter()

    @app.after_request
    def _request_observer_end(response):
        rid = getattr(g, "request_id", "") or uuid.uuid4().hex
        response.headers["X-Request-Id"] = rid
        started = getattr(g, "request_started_at", None)
        latency_ms = None
        if started is not None:
            try:
                latency_ms = round((time.perf_counter() - float(started)) * 1000.0, 2)
            except Exception:
                latency_ms = None
        payload = {
            "ts": datetime.utcnow().isoformat(),
            "request_id": rid,
            "path": request.path,
            "method": request.method,
            "status": int(response.status_code),
            "latency_ms": latency_ms,
            "user_id": getattr(g, "auth_user_id", None),
            "role": getattr(g, "auth_role", None),
            "ip_hash": _hash_ip(request.headers.get("X-Forwarded-For", request.remote_addr or ""), app.config.get("SECRET_KEY", "fliptrybe")),
            "user_agent": (request.user_agent.string or "")[:180],
        }
        app.logger.info(json.dumps(payload))
        return response
