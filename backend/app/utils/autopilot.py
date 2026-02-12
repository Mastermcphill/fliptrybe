from __future__ import annotations

from datetime import datetime, timedelta
import os

from app.extensions import db
from app.models import AutopilotSettings, PayoutRequest, NotificationQueue, User, Order, DriverJobOffer, PayoutRecipient
from app.utils.wallets import post_txn, release_reserved
from app.utils.paystack_client import initiate_transfer
from app.integrations.common import IntegrationDisabledError, IntegrationMisconfiguredError
from app.integrations.messaging.factory import build_messaging_provider


def get_settings() -> AutopilotSettings:
    env = (os.getenv("FLIPTRYBE_ENV") or os.getenv("FLASK_ENV") or "dev").strip().lower()
    row = AutopilotSettings.query.first()
    if not row:
        row = AutopilotSettings(enabled=True)
        row.payments_provider = "mock"
        row.integrations_mode = "disabled"
        row.paystack_enabled = False
        row.termii_enabled_sms = False
        row.termii_enabled_wa = False
        row.payments_mode = "mock"
        row.search_v2_mode = "off"
        row.payments_allow_legacy_fallback = env in ("staging", "stage")
        row.otel_enabled = False
        row.rate_limit_enabled = True
        db.session.add(row)
        db.session.commit()
    changed = False
    if not getattr(row, "payments_provider", None):
        row.payments_provider = "mock"
        changed = True
    if not getattr(row, "integrations_mode", None):
        row.integrations_mode = "disabled"
        changed = True
    if getattr(row, "paystack_enabled", None) is None:
        row.paystack_enabled = False
        changed = True
    if getattr(row, "termii_enabled_sms", None) is None:
        row.termii_enabled_sms = False
        changed = True
    if getattr(row, "termii_enabled_wa", None) is None:
        row.termii_enabled_wa = False
        changed = True
    if not getattr(row, "payments_mode", None):
        row.payments_mode = "mock"
        changed = True
    if not getattr(row, "search_v2_mode", None):
        row.search_v2_mode = "off"
        changed = True
    if getattr(row, "payments_allow_legacy_fallback", None) is None:
        row.payments_allow_legacy_fallback = env in ("staging", "stage")
        changed = True
    if getattr(row, "otel_enabled", None) is None:
        row.otel_enabled = False
        changed = True
    if getattr(row, "rate_limit_enabled", None) is None:
        row.rate_limit_enabled = True
        changed = True
    if changed:
        db.session.add(row)
        db.session.commit()
    return row


def should_run(settings: AutopilotSettings, min_interval_seconds: int = 25) -> bool:
    if not settings.enabled:
        return False
    if not settings.last_run_at:
        return True
    return (datetime.utcnow() - settings.last_run_at) >= timedelta(seconds=min_interval_seconds)


def _simulate_transfer(payout: PayoutRequest) -> dict:
    # Try real provider transfer if recipient exists and key is set
    try:
        rec = PayoutRecipient.query.filter_by(user_id=int(payout.user_id)).first()
        if rec and (rec.provider or 'paystack') == 'paystack':
            ref = f"PO-{int(payout.id)}-{int(datetime.utcnow().timestamp())}"
            res = initiate_transfer(float(payout.amount or 0.0), rec.recipient_code, ref)
            if res.get('ok'):
                return {"ok": True, "provider": "paystack", "reference": res.get('reference', ref)}
    except Exception:
        pass

    
    # Placeholder for Paystack/Flutterwave transfer call.
    # In a real integration, you'd call provider API and store reference.
    ref = f"SIM-{int(payout.id)}-{int(datetime.utcnow().timestamp())}"
    return {"ok": True, "provider": "SIM", "reference": ref}


def process_payouts(max_items: int = 30) -> dict:
    """Autopilot payouts: approve + pay (simulated) automatically."""
    processed = 0
    paid = 0
    failed = 0

    rows = (
        PayoutRequest.query
        .filter(PayoutRequest.status.in_(["requested", "approved"]))
        .order_by(PayoutRequest.created_at.asc())
        .limit(max_items)
        .all()
    )

    for p in rows:
        processed += 1
        try:
            # Auto-approve
            if p.status == "requested":
                p.status = "approved"

            # Consume reserved funds (was reserved at request time)
            try:
                release_reserved(int(p.user_id), float(p.amount or 0.0))
            except Exception:
                pass

            # Auto-pay
            transfer = _simulate_transfer(p)
            if not transfer.get("ok"):
                p.status = "failed"
                failed += 1
                continue

            p.provider = transfer.get("provider", "SIM")
            p.provider_reference = transfer.get("reference", "")
            p.status = "paid"

            # Ledger: debit wallet balance to reflect payout
            post_txn(int(p.user_id), float(p.amount or 0.0), kind="payout", direction="debit", reference=f"payout:{p.id}")

            db.session.add(p)
            db.session.commit()
            paid += 1
        except Exception:
            db.session.rollback()
            failed += 1

    return {"processed": processed, "paid": paid, "failed": failed}


def process_notification_queue(max_items: int = 80) -> dict:
    """Send queued notifications with retries + dead-letter.

    Status flow:
      queued -> sent
      queued -> failed (transient) -> queued (scheduled) -> ...
      queued -> dead (after max attempts)

    Channels:
      - sms/whatsapp: Termii (when TERMII_API_KEY configured)
      - in_app: marked sent (frontend pulls)
    """

    from datetime import datetime

    sent = 0
    failed = 0
    dead = 0
    now = datetime.utcnow()

    rows = (
        NotificationQueue.query
        .filter(NotificationQueue.status == "queued")
        .filter((NotificationQueue.next_attempt_at.is_(None)) | (NotificationQueue.next_attempt_at <= now))
        .order_by(NotificationQueue.created_at.asc())
        .limit(max_items)
        .all()
    )

    for r in rows:
        try:
            ch = (r.channel or "").strip().lower()
            ok = True
            detail = ""
            error_code = ""

            if ch in ("sms", "whatsapp"):
                settings = get_settings()
                try:
                    provider = build_messaging_provider(settings, channel=ch)
                    if ch == "sms":
                        result = provider.send_sms(to=r.to, message=r.message, reference=f"notif:{int(r.id)}")
                    else:
                        result = provider.send_whatsapp(to=r.to, message=r.message, reference=f"notif:{int(r.id)}")
                    ok = bool(result.ok)
                    error_code = (result.code or "").strip().upper()
                    detail = (result.message or "").strip()
                except IntegrationDisabledError as e:
                    ok = False
                    error_code = "INTEGRATION_DISABLED"
                    detail = str(e)
                    # keep queued and do not consume attempts
                    r.status = "queued"
                    r.last_error = f"{error_code}:{detail}"[:240]
                    r.next_attempt_at = now + timedelta(minutes=5)
                    db.session.add(r)
                    db.session.commit()
                    failed += 1
                    continue
                except IntegrationMisconfiguredError as e:
                    ok = False
                    error_code = "INTEGRATION_MISCONFIGURED"
                    detail = str(e)
                    r.status = "queued"
                    r.last_error = f"{error_code}:{detail}"[:240]
                    r.next_attempt_at = now + timedelta(minutes=5)
                    db.session.add(r)
                    db.session.commit()
                    failed += 1
                    continue
            elif ch == "in_app":
                ok = True
            else:
                ok = False
                error_code = "UNSUPPORTED_CHANNEL"
                detail = f"Unsupported channel: {ch}"

            if ok:
                r.status = "sent"
                r.sent_at = now
                r.last_error = None
                db.session.add(r)
                db.session.commit()
                sent += 1
                continue

            # Failure path
            r.attempt_count = int(r.attempt_count or 0) + 1
            normalized = error_code or "SEND_FAILED"
            r.last_error = f"{normalized}:{(detail or 'send_failed')}"[:240]
            max_attempts = int(r.max_attempts or 5)
            immediate_dead = normalized in (
                "TERMII_INVALID_RECIPIENT",
                "TERMII_INVALID_SENDER",
                "TERMII_AUTH_FAILED",
            )
            if immediate_dead or int(r.attempt_count) >= max_attempts:
                r.status = "dead"
                r.dead_lettered_at = now
                r.next_attempt_at = None
                db.session.add(r)
                db.session.commit()
                dead += 1
            else:
                r.schedule_next_attempt(base_seconds=15, max_seconds=3600)
                # keep status queued so it will retry later
                db.session.add(r)
                db.session.commit()
                failed += 1

        except Exception as e:
            db.session.rollback()
            try:
                r.attempt_count = int(r.attempt_count or 0) + 1
                r.last_error = ("TERMII_PROVIDER_DOWN:" + (str(e) or "exception"))[:240]
                max_attempts = int(r.max_attempts or 5)
                if int(r.attempt_count) >= max_attempts:
                    r.status = "dead"
                    r.dead_lettered_at = datetime.utcnow()
                    r.next_attempt_at = None
                    db.session.add(r)
                    db.session.commit()
                    dead += 1
                else:
                    r.status = "queued"
                    r.schedule_next_attempt(base_seconds=15, max_seconds=3600)
                    db.session.add(r)
                    db.session.commit()
                    failed += 1
            except Exception:
                db.session.rollback()
                failed += 1

    return {"sent": sent, "failed": failed, "dead": dead}

def auto_assign_drivers(max_items: int = 30) -> dict:
    """Assign available driver to orders that need a driver."""
    assigned = 0
    # Find orders that are created/paid and not assigned
    rows = (
        Order.query
        .filter(Order.driver_id.is_(None))
        .filter(Order.status.in_(["created", "paid"]))
        .order_by(Order.created_at.asc())
        .limit(max_items)
        .all()
    )
    for o in rows:
        try:
            # Try match drivers by city/state in order meta if available
            state = getattr(o, "state", None)
            city = getattr(o, "city", None)

            q = User.query.filter(User.role == "driver").filter(getattr(User, 'is_available', True) == True)
            if state:
                q = q.filter(User.state == state) if hasattr(User, "state") else q
            if city:
                q = q.filter(User.city == city) if hasattr(User, "city") else q

            driver = q.order_by(User.id.asc()).first()
            if not driver:
                continue
            offer = DriverJobOffer(order_id=int(o.id), driver_id=int(driver.id), status='offered')
            db.session.add(offer)
            # Driver must accept; do not set driver_id yet
            o.status = getattr(o, 'status', 'created')
            db.session.add(o)
            db.session.commit()
            assigned += 1
        except Exception:
            db.session.rollback()
    return {"assigned": assigned}


def tick() -> dict:
    settings = get_settings()
    if not should_run(settings):
        return {"ok": True, "skipped": True}

    payouts = process_payouts()
    queue = process_notification_queue()
    drivers = auto_assign_drivers()

    # Nightly wallet reconciliation (UTC)
    wallet_reconcile = {"skipped": True}
    try:
        from datetime import date
        from app.jobs.wallet_reconciler import reconcile_wallets

        last = settings.last_wallet_reconcile_at.date() if settings.last_wallet_reconcile_at else None
        today = datetime.utcnow().date()
        if last != today:
            wallet_reconcile = reconcile_wallets(limit=500, tolerance=0.01)
            settings.last_wallet_reconcile_at = datetime.utcnow()
    except Exception:
        wallet_reconcile = {"skipped": False, "error": "wallet_reconcile_failed"}

    settings.last_run_at = datetime.utcnow()
    db.session.add(settings)
    db.session.commit()

    return {
        "ok": True,
        "skipped": False,
        "payouts": payouts,
        "queue": queue,
        "drivers": drivers,
        "wallet_reconcile": wallet_reconcile,
    }


def auto_reassign_stale(max_items: int = 30, stale_minutes: int = 10) -> dict:
    """If an order was assigned but not progressed, reassign."""
    from datetime import datetime, timedelta
    from app.models import Order

    reassigned = 0
    cutoff = datetime.utcnow() - timedelta(minutes=stale_minutes)
    # If Order has assigned_at, use it; else use updated_at
    q = Order.query
    if hasattr(Order, "assigned_at"):
        q = q.filter(Order.assigned_at.isnot(None)).filter(Order.assigned_at <= cutoff)
    elif hasattr(Order, "updated_at"):
        q = q.filter(Order.updated_at <= cutoff)
    # statuses eligible
    if hasattr(Order, "status"):
        q = q.filter(Order.status.in_(["assigned"]))
    rows = q.limit(max_items).all()
    for o in rows:
        try:
            o.driver_id = None
            if hasattr(o, "status"):
                o.status = "paid" if getattr(o, "status", "") == "assigned" else getattr(o, "status", "created")
            db.session.add(o)
            db.session.commit()
            reassigned += 1
        except Exception:
            db.session.rollback()
    return {"reassigned": reassigned}


def expire_offers(max_items: int = 60, expiry_minutes: int = 6) -> dict:
    from datetime import datetime, timedelta
    expired = 0
    cutoff = datetime.utcnow() - timedelta(minutes=expiry_minutes)
    rows = (
        DriverJobOffer.query
        .filter(DriverJobOffer.status == "offered")
        .filter(DriverJobOffer.created_at <= cutoff)
        .order_by(DriverJobOffer.created_at.asc())
        .limit(max_items)
        .all()
    )
    for off in rows:
        try:
            off.status = "expired"
            off.decided_at = datetime.utcnow()
            db.session.add(off)
            db.session.commit()
            expired += 1
        except Exception:
            db.session.rollback()
    return {"expired": expired}


def offer_next_driver(max_items: int = 60) -> dict:
    """Escalation: for orders that have only expired/rejected offers, offer next eligible driver."""
    offered = 0
    # Find orders that are paid/created but not assigned
    orders = (
        Order.query
        .filter(Order.status.in_(["paid", "created"]))
        .order_by(Order.created_at.desc())
        .limit(max_items)
        .all()
    )
    for o in orders:
        try:
            # skip if already assigned
            if getattr(o, "driver_id", None):
                continue

            # drivers already offered
            prev = DriverJobOffer.query.filter_by(order_id=int(o.id)).all()
            prev_driver_ids = set(int(x.driver_id) for x in prev)

            # pick available drivers by locality if possible
            qs = User.query.filter_by(role="driver")
            qs = qs.filter(getattr(User, "is_available") == True) if hasattr(User, "is_available") else qs

            # locality filter if fields exist
            loc = (getattr(o, "delivery_locality", None) or getattr(o, "locality", None) or "").strip()
            if loc and hasattr(User, "locality"):
                qs = qs.filter(User.locality == loc)

            drivers = qs.limit(30).all()
            chosen = None
            for d in drivers:
                if int(d.id) in prev_driver_ids:
                    continue
                chosen = d
                break
            if not chosen:
                continue

            off = DriverJobOffer(order_id=int(o.id), driver_id=int(chosen.id), status="offered")
            db.session.add(off)
            db.session.commit()
            offered += 1

            try:
                from app.utils.messaging import enqueue_in_app, enqueue_sms, enqueue_whatsapp
                enqueue_in_app(int(chosen.id), f"New delivery offer for order #{o.id}", reference=f"order:{o.id}")
                enqueue_sms(str(chosen.id), f"FlipTrybe: New delivery offer #{o.id}", reference=f"order:{o.id}")
                enqueue_whatsapp(str(chosen.id), f"FlipTrybe: New delivery offer #{o.id}", reference=f"order:{o.id}")
            except Exception:
                pass
        except Exception:
            db.session.rollback()
            continue

    return {"offered_next": offered}
