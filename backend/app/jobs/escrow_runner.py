from __future__ import annotations

from datetime import datetime, timedelta

from app.extensions import db
import json

from app.models import Order, AuditLog, User, Listing, MerchantProfile, OrderEvent, EscrowUnlock
from app.utils.wallets import post_txn
from app.utils.commission import (
    compute_order_commissions_minor,
    money_major_to_minor,
    money_minor_to_major,
    snapshot_to_order_columns,
)
from app.utils.autopilot import get_settings
from app.utils.feature_flags import is_enabled
from app.utils.job_runs import record_job_run
from app.utils.events import log_event
import os


def _now():
    return datetime.utcnow()


def _platform_user_id() -> int:
    raw = (os.getenv("PLATFORM_USER_ID") or "").strip()
    if raw.isdigit():
        return int(raw)
    try:
        admin = User.query.filter_by(role="admin").order_by(User.id.asc()).first()
        if admin:
            return int(admin.id)
    except Exception:
        pass
    return 1


def _seller_role(user_id: int | None) -> str:
    if not user_id:
        return "buyer"
    try:
        u = User.query.get(int(user_id))
    except Exception:
        u = None
    if not u:
        return "buyer"
    role = (getattr(u, "role", "") or "buyer").strip().lower()
    if role in ("driver", "inspector"):
        return "merchant"
    return role


def _is_top_tier(merchant_id: int | None) -> bool:
    if not merchant_id:
        return False
    try:
        mp = MerchantProfile.query.filter_by(user_id=int(merchant_id)).first()
        if mp:
            return bool(getattr(mp, "is_top_tier", False))
    except Exception:
        pass
    return False


def _snapshot_from_order(order: Order) -> dict | None:
    raw = getattr(order, "commission_snapshot_json", None)
    if not raw:
        return None
    if isinstance(raw, dict):
        return dict(raw)
    try:
        parsed = json.loads(raw)
    except Exception:
        return None
    if not isinstance(parsed, dict):
        return None
    return parsed


def _apply_snapshot_to_order(order: Order, snapshot: dict) -> None:
    cols = snapshot_to_order_columns(snapshot)
    order.commission_snapshot_version = int(cols.get("commission_snapshot_version") or 1)
    order.commission_snapshot_json = json.dumps(snapshot)
    order.sale_fee_minor = int(cols.get("sale_fee_minor") or 0)
    order.sale_platform_minor = int(cols.get("sale_platform_minor") or 0)
    order.sale_seller_minor = int(cols.get("sale_seller_minor") or 0)
    order.sale_top_tier_incentive_minor = int(cols.get("sale_top_tier_incentive_minor") or 0)
    order.delivery_actor_minor = int(cols.get("delivery_actor_minor") or 0)
    order.delivery_platform_minor = int(cols.get("delivery_platform_minor") or 0)
    order.inspection_actor_minor = int(cols.get("inspection_actor_minor") or 0)
    order.inspection_platform_minor = int(cols.get("inspection_platform_minor") or 0)


def _ensure_commission_snapshot(order: Order, listing: Listing | None = None) -> dict:
    existing = _snapshot_from_order(order)
    if existing is not None:
        return existing

    sale_kind = "declutter"
    if listing is not None:
        listing_type = str(getattr(listing, "listing_type", "") or "").strip().lower()
        if listing_type == "shortlet":
            sale_kind = "shortlet"

    snapshot = compute_order_commissions_minor(
        sale_kind=sale_kind,
        sale_charge_minor=money_major_to_minor(float(getattr(order, "amount", 0.0) or 0.0)),
        delivery_minor=money_major_to_minor(float(getattr(order, "delivery_fee", 0.0) or 0.0)),
        inspection_minor=money_major_to_minor(float(getattr(order, "inspection_fee", 0.0) or 0.0)),
        is_top_tier=_is_top_tier(getattr(order, "merchant_id", None)),
    )
    _apply_snapshot_to_order(order, snapshot)
    return snapshot


def _credit_seller(order: Order, listing: Listing | None, ref: str, order_amount: float) -> None:
    snapshot = _ensure_commission_snapshot(order, listing)
    sale = snapshot.get("sale") if isinstance(snapshot.get("sale"), dict) else {}
    seller_minor = int(sale.get("seller_minor") or 0)
    platform_minor = int(sale.get("platform_minor") or 0)
    top_tier_minor = int(sale.get("top_tier_incentive_minor") or 0)

    if seller_minor > 0:
        post_txn(
            user_id=int(order.merchant_id),
            direction="credit",
            amount=money_minor_to_major(seller_minor),
            kind="order_sale",
            reference=ref,
            note=f"Order sale for order #{int(order.id)}",
        )
    if top_tier_minor > 0:
        post_txn(
            user_id=int(order.merchant_id),
            direction="credit",
            amount=money_minor_to_major(top_tier_minor),
            kind="top_tier_incentive",
            reference=ref,
            note=f"Top-tier incentive for order #{int(order.id)}",
        )
    if platform_minor > 0:
        post_txn(
            user_id=_platform_user_id(),
            direction="credit",
            amount=money_minor_to_major(platform_minor),
            kind="platform_fee",
            reference=ref,
            note=f"Platform fee for order #{int(order.id)}",
        )


def _credit_driver(order: Order, ref: str, delivery_fee: float) -> None:
    snapshot = _ensure_commission_snapshot(order)
    delivery = snapshot.get("delivery") if isinstance(snapshot.get("delivery"), dict) else {}
    actor_minor = int(delivery.get("actor_minor") or 0)
    platform_minor = int(delivery.get("platform_minor") or 0)

    if actor_minor > 0 and order.driver_id:
        post_txn(
            user_id=int(order.driver_id),
            direction="credit",
            amount=money_minor_to_major(actor_minor),
            kind="delivery_fee",
            reference=ref,
            note=f"Delivery fee for order #{int(order.id)}",
        )
    if platform_minor > 0:
        post_txn(
            user_id=_platform_user_id(),
            direction="credit",
            amount=money_minor_to_major(platform_minor),
            kind="delivery_commission",
            reference=ref,
            note=f"Delivery platform share for order #{int(order.id)}",
        )


def _hold_order_into_escrow(order: Order) -> None:
    """Idempotently mark an order as HELD.

    IMPORTANT: This does not charge a card. It assumes payment already happened and
    we are now accounting internally.
    """
    if (order.escrow_status or "NONE") != "NONE":
        return
    order.escrow_status = "HELD"
    order.escrow_hold_amount = float(order.amount or 0.0) + float(order.delivery_fee or 0.0) + float(getattr(order, "inspection_fee", 0.0) or 0.0)
    order.escrow_held_at = _now()
    if order.inspection_required:
        order.release_condition = "INSPECTION_PASS"
    elif not (order.release_condition or "").strip():
        order.release_condition = "BUYER_CONFIRM"
    order.updated_at = _now()
    log_event(
        "escrow_funded",
        subject_type="order",
        subject_id=int(order.id) if getattr(order, "id", None) is not None else None,
        idempotency_key=f"escrow_funded:{int(order.id)}" if getattr(order, "id", None) is not None else None,
        metadata={"escrow_hold_amount": float(order.escrow_hold_amount or 0.0)},
    )


def _release_escrow(order: Order) -> None:
    if (order.escrow_status or "NONE") != "HELD":
        return
    ref = f"order:{int(order.id)}"
    order_amount = float(order.amount or 0.0)
    delivery_fee = float(order.delivery_fee or 0.0)
    listing = None
    if order.listing_id:
        try:
            listing = Listing.query.get(int(order.listing_id))
        except Exception:
            listing = None

    _credit_seller(order, listing, ref, order_amount)
    _credit_driver(order, ref, delivery_fee)
    _settle_inspection_fee(order)

    order.escrow_status = "RELEASED"
    order.escrow_release_at = _now()
    order.updated_at = _now()
    _event_once(int(order.id), "escrow_released", "Escrow released")
    log_event(
        "settlement_applied",
        subject_type="order",
        subject_id=int(order.id),
        idempotency_key=f"settlement_applied:{int(order.id)}:released",
        metadata={"escrow_status": "RELEASED"},
    )


def _refund_escrow(order: Order) -> None:
    if (order.escrow_status or "NONE") != "HELD":
        return
    amount = float(order.escrow_hold_amount or 0.0)
    if amount <= 0:
        order.escrow_status = "REFUNDED"
        order.escrow_refund_at = _now()
        return
    post_txn(
        user_id=int(order.buyer_id),
        direction="credit",
        amount=amount,
        kind="escrow_refund",
        reference=f"order:{int(order.id)}",
        note=f"Escrow refund for order #{int(order.id)}",
    )
    order.escrow_status = "REFUNDED"
    order.escrow_refund_at = _now()
    order.updated_at = _now()
    _event_once(int(order.id), "escrow_refunded", "Escrow refunded")
    log_event(
        "settlement_applied",
        subject_type="order",
        subject_id=int(order.id),
        idempotency_key=f"settlement_applied:{int(order.id)}:refunded",
        metadata={"escrow_status": "REFUNDED"},
    )


def _event_once(order_id: int, event: str, note: str = "") -> None:
    try:
        key = f"order:{int(order_id)}:{event}:system"
        existing = OrderEvent.query.filter_by(idempotency_key=key[:160]).first()
        if not existing:
            existing = OrderEvent.query.filter_by(order_id=int(order_id), event=event).first()
        if existing:
            return
        row = OrderEvent(
            order_id=int(order_id),
            actor_user_id=None,
            event=event,
            note=note[:240],
            idempotency_key=key[:160],
        )
        db.session.add(row)
        db.session.commit()
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass


def _settle_inspection_fee(order: Order) -> None:
    snapshot = _ensure_commission_snapshot(order)
    inspection = snapshot.get("inspection") if isinstance(snapshot.get("inspection"), dict) else {}
    actor_minor = int(inspection.get("actor_minor") or 0)
    platform_minor = int(inspection.get("platform_minor") or 0)
    if actor_minor > 0 and order.inspector_id:
        post_txn(
            user_id=int(order.inspector_id),
            direction="credit",
            amount=money_minor_to_major(actor_minor),
            kind="inspection_fee",
            reference=f"inspection:{int(order.id)}",
            note=f"Inspection fee for order #{int(order.id)}",
        )
    if platform_minor > 0:
        post_txn(
            user_id=_platform_user_id(),
            direction="credit",
            amount=money_minor_to_major(platform_minor),
            kind="inspection_commission",
            reference=f"inspection:{int(order.id)}",
            note=f"Inspection platform share for order #{int(order.id)}",
        )


def _inspection_unlock_ready(order_id: int) -> bool:
    try:
        row = EscrowUnlock.query.filter_by(order_id=int(order_id), step="inspection_inspector").first()
        return bool(row and row.unlocked_at)
    except Exception:
        return False


def run_escrow_automation(*, limit: int = 500) -> dict:
    """Run escrow automation for HELD orders.

    Rules:
      - If inspection_outcome == PASS: release when release_condition allows.
      - If inspection_outcome in (FAIL, FRAUD): refund.
      - If inspection_outcome == PASS and release_condition == TIMEOUT: release after timeout.
      - Otherwise: do nothing.
    """

    started_at = _now()
    try:
        settings = get_settings()
    except Exception:
        settings = None
    if settings is not None and not is_enabled("jobs.escrow_runner_enabled", default=True, settings=settings):
        result = {
            "ok": False,
            "disabled": True,
            "processed": 0,
            "released": 0,
            "refunded": 0,
            "skipped": 0,
            "errors": 0,
            "ts": _now().isoformat(),
        }
        record_job_run(
            job_name="escrow_runner",
            ok=False,
            started_at=started_at,
            error="disabled_by_flag",
        )
        return result

    processed = 0
    released = 0
    refunded = 0
    skipped = 0
    errors = 0

    rows = (
        Order.query.filter_by(escrow_status="HELD")
        .order_by(Order.id.asc())
        .limit(int(limit))
        .all()
    )

    for o in rows:
        processed += 1
        try:
            status = (o.status or "").strip().lower()
            if status in ("delivered", "completed", "closed") and (o.escrow_status or "NONE") == "HELD":
                o.escrow_status = "DISPUTED"
                o.escrow_disputed_at = _now()
                o.updated_at = _now()
                _event_once(int(o.id), "escrow_disputed", f"Escrow disputed due to status {status}")
                try:
                    db.session.add(
                        AuditLog(
                            actor_user_id=None,
                            action="escrow_violation",
                            target_type="order",
                            target_id=int(o.id),
                            meta=json.dumps({
                                "order_id": int(o.id),
                                "status": status,
                                "escrow_status": "HELD",
                                "ts": _now().isoformat(),
                            }),
                        )
                    )
                except Exception:
                    pass
                skipped += 1
                continue

            outcome = (o.inspection_outcome or "NONE").upper()
            cond = (o.release_condition or "INSPECTION_PASS").upper()

            # Refund is immediate on FAIL/FRAUD.
            if outcome in ("FAIL", "FRAUD"):
                _settle_inspection_fee(o)
                _refund_escrow(o)
                refunded += 1
                continue

            if outcome == "PASS":
                if cond == "INSPECTION_PASS":
                    if not _inspection_unlock_ready(int(o.id)):
                        skipped += 1
                        continue
                    _settle_inspection_fee(o)
                    _release_escrow(o)
                    released += 1
                    continue
                _settle_inspection_fee(o)
                if cond == "TIMEOUT":
                    held_at = o.escrow_held_at or o.created_at
                    timeout = timedelta(hours=int(o.release_timeout_hours or 48))
                    if held_at and _now() >= (held_at + timeout):
                        _release_escrow(o)
                        released += 1
                        continue
                # BUYER_CONFIRM / ADMIN are not auto.
                skipped += 1
                continue

            skipped += 1
        except Exception:
            errors += 1
            db.session.rollback()

    try:
        db.session.commit()
    except Exception:
        db.session.rollback()
        errors += 1

    result = {
        "ok": True,
        "processed": processed,
        "released": released,
        "refunded": refunded,
        "skipped": skipped,
        "errors": errors,
        "ts": _now().isoformat(),
    }
    record_job_run(
        job_name="escrow_runner",
        ok=errors == 0,
        started_at=started_at,
        error=None if errors == 0 else f"errors={errors}",
    )
    return result


def run_once(*, limit: int = 500) -> dict:
    """Backward-compatible alias used by smoke scripts."""
    from app import create_app

    app = create_app()
    with app.app_context():
        return run_escrow_automation(limit=limit)
