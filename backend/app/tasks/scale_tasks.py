from __future__ import annotations

import hashlib
import json
import os
import time
from datetime import datetime

from celery import shared_task
from flask import current_app

from app.utils.idempotency import lookup_response, store_response
from app.utils.termii_client import send_termii_message


def _task_log(task_name: str, *, status: str, started_at: float, trace_id: str = "", **extra):
    duration_ms = int(max(0.0, (time.perf_counter() - float(started_at))) * 1000.0)
    payload = {
        "task_name": task_name,
        "status": status,
        "duration_ms": duration_ms,
        "trace_id": str(trace_id or ""),
        "timestamp": datetime.utcnow().isoformat(),
    }
    payload.update(extra or {})
    try:
        current_app.logger.info(json.dumps(payload))
    except Exception:
        pass


def _retry_countdown(retries: int) -> int:
    # Exponential backoff with cap.
    return int(min(900, max(5, 5 * (2 ** int(max(0, retries))))))


@shared_task(
    bind=True,
    name="app.tasks.scale_tasks.send_termii_message",
    max_retries=5,
)
def send_termii_message_task(
    self,
    *,
    channel: str,
    to: str,
    message: str,
    reference: str = "",
    trace_id: str = "",
):
    started = time.perf_counter()
    try:
        ok, detail = send_termii_message(
            channel=str(channel or "generic"),
            to=str(to or ""),
            message=str(message or ""),
        )
        if ok:
            _task_log(
                "send_termii_message",
                status="ok",
                started_at=started,
                trace_id=trace_id,
                channel=channel,
                reference=reference,
            )
            return {"ok": True, "detail": str(detail or "queued")}
        if int(self.request.retries or 0) < int(self.max_retries or 0):
            countdown = _retry_countdown(int(self.request.retries or 0))
            _task_log(
                "send_termii_message",
                status="retrying",
                started_at=started,
                trace_id=trace_id,
                channel=channel,
                reference=reference,
                detail=str(detail or ""),
                countdown=countdown,
            )
            raise self.retry(exc=RuntimeError(str(detail or "termii_send_failed")), countdown=countdown)
        _task_log(
            "send_termii_message",
            status="failed",
            started_at=started,
            trace_id=trace_id,
            channel=channel,
            reference=reference,
            detail=str(detail or ""),
        )
        return {"ok": False, "detail": str(detail or "failed")}
    except Exception as exc:
        if int(self.request.retries or 0) < int(self.max_retries or 0):
            countdown = _retry_countdown(int(self.request.retries or 0))
            _task_log(
                "send_termii_message",
                status="retrying",
                started_at=started,
                trace_id=trace_id,
                channel=channel,
                reference=reference,
                detail=str(exc),
                countdown=countdown,
            )
            raise self.retry(exc=exc, countdown=countdown)
        _task_log(
            "send_termii_message",
            status="failed",
            started_at=started,
            trace_id=trace_id,
            channel=channel,
            reference=reference,
            detail=str(exc),
        )
        return {"ok": False, "detail": str(exc)}


@shared_task(
    bind=True,
    name="app.tasks.scale_tasks.process_paystack_webhook",
    max_retries=5,
)
def process_paystack_webhook_task(
    self,
    *,
    payload: dict,
    raw_text: str = "",
    signature: str | None = None,
    source: str = "api/payments/webhook/paystack:queued",
    trace_id: str = "",
):
    started = time.perf_counter()
    event_id = ""
    try:
        event_id = str(payload.get("id") or payload.get("event_id") or "").strip()
    except Exception:
        event_id = ""
    if not event_id:
        reference = ""
        try:
            reference = str((payload.get("data") or {}).get("reference") or "").strip()
        except Exception:
            reference = ""
        seed = f"{source}:{reference}:{json.dumps(payload, sort_keys=True, separators=(',', ':'), default=str)}"
        event_id = hashlib.sha256(seed.encode("utf-8")).hexdigest()[:64]

    idem = lookup_response(
        None,
        "/api/payments/webhook/paystack",
        payload,
        scope="webhook:paystack",
        idempotency_key=event_id,
        require_header=False,
    )
    if idem and idem[0] == "hit":
        _task_log(
            "process_paystack_webhook",
            status="idempotent_hit",
            started_at=started,
            trace_id=trace_id,
            event_id=event_id,
        )
        return {"ok": True, "replayed": True, "event_id": event_id}
    if idem and idem[0] == "conflict":
        _task_log(
            "process_paystack_webhook",
            status="idempotency_conflict",
            started_at=started,
            trace_id=trace_id,
            event_id=event_id,
        )
        return idem[1]
    idem_row = idem[1] if idem and idem[0] == "miss" else None

    from app.segments.segment_payments import process_paystack_webhook

    try:
        body, code = process_paystack_webhook(
            payload=payload if isinstance(payload, dict) else {},
            raw=(raw_text or "").encode("utf-8"),
            signature=signature,
            source=source,
        )
        if idem_row is not None:
            store_response(idem_row, body, int(code))
        if int(code) >= 500 and int(self.request.retries or 0) < int(self.max_retries or 0):
            countdown = _retry_countdown(int(self.request.retries or 0))
            _task_log(
                "process_paystack_webhook",
                status="retrying",
                started_at=started,
                trace_id=trace_id,
                event_id=event_id,
                status_code=int(code),
                countdown=countdown,
            )
            raise self.retry(exc=RuntimeError(f"webhook_status_{int(code)}"), countdown=countdown)
        _task_log(
            "process_paystack_webhook",
            status="ok",
            started_at=started,
            trace_id=trace_id,
            event_id=event_id,
            status_code=int(code),
        )
        return {"ok": True, "event_id": event_id, "status_code": int(code), "body": body}
    except Exception as exc:
        if int(self.request.retries or 0) < int(self.max_retries or 0):
            countdown = _retry_countdown(int(self.request.retries or 0))
            _task_log(
                "process_paystack_webhook",
                status="retrying",
                started_at=started,
                trace_id=trace_id,
                event_id=event_id,
                detail=str(exc),
                countdown=countdown,
            )
            raise self.retry(exc=exc, countdown=countdown)
        _task_log(
            "process_paystack_webhook",
            status="failed",
            started_at=started,
            trace_id=trace_id,
            event_id=event_id,
            detail=str(exc),
        )
        raise


@shared_task(
    bind=True,
    name="app.tasks.scale_tasks.run_escrow_settlement",
    max_retries=3,
)
def run_escrow_settlement(self, *, trace_id: str = ""):
    started = time.perf_counter()
    limit = 50
    try:
        limit = int((os.getenv("ESCROW_SETTLEMENT_LIMIT") or "50").strip() or 50)
    except Exception:
        limit = 50
    from app.jobs.escrow_runner import run_escrow_automation

    try:
        result = run_escrow_automation(limit=max(1, min(limit, 500)))
        _task_log(
            "run_escrow_settlement",
            status="ok" if bool(result.get("ok")) else "failed",
            started_at=started,
            trace_id=trace_id,
            limit=limit,
        )
        return result
    except Exception as exc:
        if int(self.request.retries or 0) < int(self.max_retries or 0):
            countdown = _retry_countdown(int(self.request.retries or 0))
            _task_log(
                "run_escrow_settlement",
                status="retrying",
                started_at=started,
                trace_id=trace_id,
                detail=str(exc),
                countdown=countdown,
            )
            raise self.retry(exc=exc, countdown=countdown)
        _task_log(
            "run_escrow_settlement",
            status="failed",
            started_at=started,
            trace_id=trace_id,
            detail=str(exc),
        )
        raise
