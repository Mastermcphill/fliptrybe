from __future__ import annotations

from datetime import datetime
import os

from flask import Blueprint, jsonify, request, current_app

from app.extensions import db
from app.models import Wallet, Transaction
from app.segments.segment_payments import process_paystack_webhook
from app.utils.autopilot import get_settings
from app.services.risk_engine_service import record_event
from app.utils.observability import get_request_id

webhooks_bp = Blueprint("webhooks_bp", __name__, url_prefix="/api/webhooks")

_WEBHOOKS_INIT_DONE = False


@webhooks_bp.before_app_request
def _ensure_tables_once():
    global _WEBHOOKS_INIT_DONE
    if _WEBHOOKS_INIT_DONE:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _WEBHOOKS_INIT_DONE = True


def _legacy_credit_wallet_from_metadata(payload: dict) -> bool:
    data = payload.get("data") or {}
    meta = data.get("metadata") or {}
    user_id = meta.get("user_id")
    try:
        uid = int(user_id)
    except Exception:
        return False

    amount_kobo = data.get("amount") or 0
    try:
        gross = float(amount_kobo) / 100.0
    except Exception:
        gross = 0.0
    if gross <= 0:
        return False

    wallet = Wallet.query.filter_by(user_id=uid).first()
    if not wallet:
        wallet = Wallet(user_id=uid, balance=0.0)
        db.session.add(wallet)
        db.session.commit()

    wallet.balance = float(wallet.balance or 0.0) + gross
    tx = Transaction(
        wallet_id=int(wallet.id),
        amount=gross,
        gross_amount=gross,
        net_amount=gross,
        commission_total=0.0,
        purpose="topup",
        direction="credit",
        reference=f"legacy_paystack:{int(datetime.utcnow().timestamp())}",
        created_at=datetime.utcnow(),
    )
    db.session.add(wallet)
    db.session.add(tx)
    db.session.commit()
    return True


@webhooks_bp.post("/paystack")
def paystack_webhook():
    try:
        raw = request.get_data() or b"{}"
        sig = request.headers.get("X-Paystack-Signature")
        payload = request.get_json(silent=True) or {}

        if (os.getenv("PAYSTACK_WEBHOOK_QUEUE") or "true").strip().lower() in ("1", "true", "yes", "on"):
            try:
                from app.tasks.scale_tasks import process_paystack_webhook_task

                process_paystack_webhook_task.delay(
                    payload=payload if isinstance(payload, dict) else {},
                    raw_text=(raw or b"").decode("utf-8", errors="ignore"),
                    signature=sig,
                    source="api/webhooks/paystack:queued",
                    trace_id=get_request_id(),
                )
                return jsonify({"ok": True, "queued": True, "trace_id": get_request_id()}), 200
            except Exception:
                try:
                    db.session.rollback()
                except Exception:
                    pass

        body, status = process_paystack_webhook(payload=payload, raw=raw, signature=sig, source="api/webhooks/paystack")

        # Backward compatibility: old webhook payloads may not include a PaymentIntent reference.
        if int(status) == 200 and bool(body.get("ignored")) and isinstance(payload, dict) and (payload.get("data") or {}).get("metadata"):
            try:
                settings = get_settings()
                allow_legacy = bool(getattr(settings, "payments_allow_legacy_fallback", False))
                if not allow_legacy:
                    try:
                        record_event(
                            "webhook_legacy_fallback_blocked",
                            context={
                                "provider": "paystack",
                                "reason_code": "LEGACY_FALLBACK_DISABLED",
                                "reference": ((payload.get("data") or {}).get("reference") or ""),
                            },
                            request_id=request.headers.get("X-Request-Id"),
                        )
                    except Exception:
                        db.session.rollback()
                    body = {
                        "ok": False,
                        "error": "LEGACY_FALLBACK_DISABLED",
                        "message": "Legacy fallback is disabled; requires admin review",
                    }
                    status = 409
                elif _legacy_credit_wallet_from_metadata(payload):
                    body = {"ok": True, "legacy": True}
            except Exception:
                db.session.rollback()

        return jsonify(body), int(status)
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        current_app.logger.exception("legacy_paystack_webhook_route_failed")
        return jsonify({"ok": False, "error": "WEBHOOK_HANDLER_FAILED"}), 200


@webhooks_bp.post("/stripe")
def stripe_webhook():
    return jsonify({"ok": True, "ignored": True, "provider": "stripe"}), 200
