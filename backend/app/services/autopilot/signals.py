from __future__ import annotations

import hashlib
import json
from collections import defaultdict
from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP

from app.models import Listing, Order, PayoutRequest, Shortlet, ShortletBooking, User, WalletTxn
from app.models.risk import Dispute
from app.services.commission_policy_service import resolve_commission_policy
from app.services.simulation.liquidity_simulator import get_liquidity_baseline, run_liquidity_simulation


PAID_ORDER_STATES = (
    "paid",
    "merchant_accepted",
    "driver_assigned",
    "picked_up",
    "delivered",
    "completed",
)

PAID_BOOKING_STATES = ("paid", "confirmed")


def _minor(amount) -> int:
    try:
        parsed = Decimal(str(amount or 0))
    except Exception:
        parsed = Decimal("0")
    return int((parsed * Decimal("100")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _pct_delta(current: float, previous: float) -> float:
    if previous == 0:
        if current == 0:
            return 0.0
        return 100.0
    return ((current - previous) / abs(previous)) * 100.0


def _norm_city(value: str | None) -> str:
    text = (value or "").strip()
    if not text:
        return "all"
    return text


def _seller_type(role: str | None) -> str:
    return "merchant" if (role or "").strip().lower() == "merchant" else "user"


def _segment_key(applies_to: str, seller_type: str, city: str) -> tuple[str, str, str]:
    return (applies_to, seller_type, _norm_city(city))


def _new_segment(applies_to: str, seller_type: str, city: str) -> dict:
    return {
        "applies_to": applies_to,
        "seller_type": seller_type,
        "city": _norm_city(city),
        "order_count": 0,
        "gmv_minor": 0,
        "unique_buyers": set(),
        "active_listings_count": 0,
        "new_listings_7d": 0,
        "sellers_active_30d": set(),
        "sellers_recent_90d": set(),
        "dispute_count": 0,
        "refund_minor": 0,
    }


def _segment_map_to_jsonable(raw: dict[tuple[str, str, str], dict], prev: dict[tuple[str, str, str], dict], liquidity: dict) -> list[dict]:
    rows: list[dict] = []
    for key in sorted(raw.keys()):
        row = raw[key]
        previous = prev.get(key, {})
        order_count = int(row.get("order_count") or 0)
        gmv_minor = int(row.get("gmv_minor") or 0)
        unique_buyers = len(row.get("unique_buyers") or set())
        active_listings = int(row.get("active_listings_count") or 0)
        sellers_active_30 = len(row.get("sellers_active_30d") or set())
        sellers_recent_90 = len(row.get("sellers_recent_90d") or set())
        sellers_inactive_30 = max(0, sellers_recent_90 - sellers_active_30)
        previous_order_count = int(previous.get("order_count") or 0)
        previous_gmv_minor = int(previous.get("gmv_minor") or 0)
        previous_active = int(previous.get("active_listings_count") or 0)
        conversion_per_listing = float(order_count / active_listings) if active_listings > 0 else 0.0
        conversion_per_buyer = float(order_count / unique_buyers) if unique_buyers > 0 else 0.0
        resolved = resolve_commission_policy(
            applies_to=row.get("applies_to") or "declutter",
            seller_type=row.get("seller_type") or "all",
            city="" if (row.get("city") or "all") == "all" else (row.get("city") or ""),
        )
        rows.append(
            {
                "applies_to": row.get("applies_to") or "declutter",
                "seller_type": row.get("seller_type") or "all",
                "city": row.get("city") or "all",
                "order_count": order_count,
                "gmv_minor": gmv_minor,
                "unique_buyers": unique_buyers,
                "active_listings_count": active_listings,
                "new_listings_7d": int(row.get("new_listings_7d") or 0),
                "conversion_orders_per_active_listing": round(conversion_per_listing, 4),
                "conversion_orders_per_unique_buyers": round(conversion_per_buyer, 4),
                "sellers_with_no_activity_30d": sellers_inactive_30,
                "sellers_active_30d": sellers_active_30,
                "previous_order_count": previous_order_count,
                "previous_gmv_minor": previous_gmv_minor,
                "previous_active_listings_count": previous_active,
                "orders_delta_pct": round(_pct_delta(order_count, previous_order_count), 3),
                "gmv_delta_pct": round(_pct_delta(gmv_minor, previous_gmv_minor), 3),
                "active_listings_delta_pct": round(_pct_delta(active_listings, previous_active), 3),
                "liquidity": {
                    "withdrawal_ratio_30d": float(liquidity.get("withdrawal_ratio_30d") or 0.0),
                    "float_min_30d_minor": int(liquidity.get("float_min_30d_minor") or 0),
                    "payout_pressure": float(liquidity.get("payout_pressure") or 0.0),
                    "days_to_negative": liquidity.get("days_to_negative"),
                },
                "quality": {
                    "dispute_count": int(row.get("dispute_count") or 0),
                    "refund_minor": int(row.get("refund_minor") or 0),
                    "chargeback_rate": float(row.get("chargeback_rate") or 0.0),
                },
                "current_policy": resolved.to_dict(),
            }
        )
    return rows


def _apply_order_row(
    rows: list[Order],
    listings_by_id: dict[int, Listing],
    roles: dict[int, str],
    result: dict[tuple[str, str, str], dict],
):
    for row in rows:
        listing = listings_by_id.get(int(row.listing_id or 0))
        seller_id = int(row.merchant_id or 0)
        seller_type = _seller_type(roles.get(seller_id))
        city = _norm_city(getattr(listing, "city", None))
        amount_minor = _minor(getattr(row, "total_price", 0.0) or getattr(row, "amount", 0.0))
        for city_key in (city, "all"):
            key = _segment_key("declutter", seller_type, city_key)
            bucket = result.setdefault(key, _new_segment("declutter", seller_type, city_key))
            bucket["order_count"] += 1
            bucket["gmv_minor"] += int(max(0, amount_minor))
            buyer_id = int(getattr(row, "buyer_id", 0) or 0)
            if buyer_id > 0:
                bucket["unique_buyers"].add(buyer_id)


def _apply_booking_row(
    rows: list[ShortletBooking],
    shortlets_by_id: dict[int, Shortlet],
    roles: dict[int, str],
    result: dict[tuple[str, str, str], dict],
):
    for row in rows:
        shortlet = shortlets_by_id.get(int(row.shortlet_id or 0))
        if not shortlet:
            continue
        seller_id = int(getattr(shortlet, "owner_id", 0) or 0)
        seller_type = _seller_type(roles.get(seller_id))
        city = _norm_city(getattr(shortlet, "city", None))
        amount_minor = _minor(getattr(row, "total_amount", 0.0))
        for city_key in (city, "all"):
            key = _segment_key("shortlet", seller_type, city_key)
            bucket = result.setdefault(key, _new_segment("shortlet", seller_type, city_key))
            bucket["order_count"] += 1
            bucket["gmv_minor"] += int(max(0, amount_minor))
            buyer_id = int(getattr(row, "user_id", 0) or 0)
            if buyer_id > 0:
                bucket["unique_buyers"].add(buyer_id)


def _apply_supply_counts(
    *,
    now: datetime,
    window_days: int,
    roles: dict[int, str],
    current: dict[tuple[str, str, str], dict],
    previous: dict[tuple[str, str, str], dict],
):
    seven_days_ago = now - timedelta(days=7)
    previous_cutoff = now - timedelta(days=max(1, int(window_days)))

    listings = Listing.query.filter(Listing.is_active == True).all()  # noqa: E712
    shortlets = Shortlet.query.all()

    for row in listings:
        seller_type = _seller_type(roles.get(int(getattr(row, "user_id", 0) or 0)))
        city = _norm_city(getattr(row, "city", None))
        created_at = getattr(row, "created_at", None)
        for city_key in (city, "all"):
            key = _segment_key("declutter", seller_type, city_key)
            bucket = current.setdefault(key, _new_segment("declutter", seller_type, city_key))
            bucket["active_listings_count"] += 1
            if created_at and created_at >= seven_days_ago:
                bucket["new_listings_7d"] += 1

            prev_bucket = previous.setdefault(key, _new_segment("declutter", seller_type, city_key))
            if created_at is None or created_at <= previous_cutoff:
                prev_bucket["active_listings_count"] += 1

    for row in shortlets:
        seller_type = _seller_type(roles.get(int(getattr(row, "owner_id", 0) or 0)))
        city = _norm_city(getattr(row, "city", None))
        created_at = getattr(row, "created_at", None)
        for city_key in (city, "all"):
            key = _segment_key("shortlet", seller_type, city_key)
            bucket = current.setdefault(key, _new_segment("shortlet", seller_type, city_key))
            bucket["active_listings_count"] += 1
            if created_at and created_at >= seven_days_ago:
                bucket["new_listings_7d"] += 1

            prev_bucket = previous.setdefault(key, _new_segment("shortlet", seller_type, city_key))
            if created_at is None or created_at <= previous_cutoff:
                prev_bucket["active_listings_count"] += 1


def _apply_seller_activity(now: datetime, roles: dict[int, str], current: dict[tuple[str, str, str], dict]):
    last_30 = now - timedelta(days=30)
    last_90 = now - timedelta(days=90)

    order_rows = Order.query.filter(Order.status.in_(PAID_ORDER_STATES), Order.created_at >= last_90).all()
    listing_ids = [int(o.listing_id) for o in order_rows if getattr(o, "listing_id", None)]
    listings_by_id = {
        int(row.id): row
        for row in Listing.query.filter(Listing.id.in_(listing_ids)).all()
    } if listing_ids else {}
    for row in order_rows:
        seller_id = int(getattr(row, "merchant_id", 0) or 0)
        seller_type = _seller_type(roles.get(seller_id))
        listing = listings_by_id.get(int(getattr(row, "listing_id", 0) or 0))
        city = _norm_city(getattr(listing, "city", None))
        for city_key in (city, "all"):
            key = _segment_key("declutter", seller_type, city_key)
            bucket = current.setdefault(key, _new_segment("declutter", seller_type, city_key))
            bucket["sellers_recent_90d"].add(seller_id)
            if getattr(row, "created_at", None) and row.created_at >= last_30:
                bucket["sellers_active_30d"].add(seller_id)

    booking_rows = ShortletBooking.query.filter(ShortletBooking.created_at >= last_90).all()
    shortlet_ids = [int(b.shortlet_id) for b in booking_rows if getattr(b, "shortlet_id", None)]
    shortlets_by_id = {
        int(row.id): row
        for row in Shortlet.query.filter(Shortlet.id.in_(shortlet_ids)).all()
    } if shortlet_ids else {}
    for row in booking_rows:
        shortlet = shortlets_by_id.get(int(getattr(row, "shortlet_id", 0) or 0))
        if not shortlet:
            continue
        seller_id = int(getattr(shortlet, "owner_id", 0) or 0)
        seller_type = _seller_type(roles.get(seller_id))
        city = _norm_city(getattr(shortlet, "city", None))
        for city_key in (city, "all"):
            key = _segment_key("shortlet", seller_type, city_key)
            bucket = current.setdefault(key, _new_segment("shortlet", seller_type, city_key))
            bucket["sellers_recent_90d"].add(seller_id)
            if getattr(row, "created_at", None) and row.created_at >= last_30:
                bucket["sellers_active_30d"].add(seller_id)


def _apply_quality_signals(start: datetime, end: datetime, current: dict[tuple[str, str, str], dict]):
    disputes = Dispute.query.filter(Dispute.created_at >= start, Dispute.created_at < end).all()
    dispute_count = int(len(disputes))
    refunds = WalletTxn.query.filter(
        WalletTxn.created_at >= start,
        WalletTxn.created_at < end,
        WalletTxn.kind.ilike("%refund%"),
    ).all()
    refund_minor = int(sum(abs(_minor(getattr(row, "amount", 0.0))) for row in refunds))

    for bucket in current.values():
        gmv_minor = int(bucket.get("gmv_minor") or 0)
        rate = (float(refund_minor) / float(gmv_minor)) if gmv_minor > 0 else 0.0
        bucket["dispute_count"] = dispute_count
        bucket["refund_minor"] = refund_minor
        bucket["chargeback_rate"] = round(max(0.0, rate), 6)


def _build_segment_rows(start: datetime, end: datetime, now: datetime, roles: dict[int, str]) -> dict[tuple[str, str, str], dict]:
    rows: dict[tuple[str, str, str], dict] = {}

    order_rows = (
        Order.query.filter(Order.created_at >= start, Order.created_at < end, Order.status.in_(PAID_ORDER_STATES)).all()
    )
    listing_ids = [int(o.listing_id) for o in order_rows if getattr(o, "listing_id", None)]
    listings_by_id = {
        int(row.id): row
        for row in Listing.query.filter(Listing.id.in_(listing_ids)).all()
    } if listing_ids else {}
    _apply_order_row(order_rows, listings_by_id, roles, rows)

    booking_rows = (
        ShortletBooking.query.filter(
            ShortletBooking.created_at >= start,
            ShortletBooking.created_at < end,
            ShortletBooking.payment_status.in_(PAID_BOOKING_STATES),
        ).all()
    )
    shortlet_ids = [int(b.shortlet_id) for b in booking_rows if getattr(b, "shortlet_id", None)]
    shortlets_by_id = {
        int(row.id): row
        for row in Shortlet.query.filter(Shortlet.id.in_(shortlet_ids)).all()
    } if shortlet_ids else {}
    _apply_booking_row(booking_rows, shortlets_by_id, roles, rows)
    _apply_quality_signals(start, end, rows)
    return rows


def compute_autopilot_signals(window_days: int = 30) -> dict:
    window = max(7, min(int(window_days or 30), 90))
    now = datetime.utcnow()
    start = now - timedelta(days=window)
    prev_start = start - timedelta(days=window)
    prev_end = start

    users = User.query.with_entities(User.id, User.role).all()
    roles = {int(uid): (role or "buyer").strip().lower() for uid, role in users}

    current = _build_segment_rows(start=start, end=now, now=now, roles=roles)
    previous = _build_segment_rows(start=prev_start, end=prev_end, now=now, roles=roles)
    _apply_supply_counts(now=now, window_days=window, roles=roles, current=current, previous=previous)
    _apply_seller_activity(now=now, roles=roles, current=current)

    baseline = get_liquidity_baseline()
    avg_daily_commission = int(baseline.get("avg_daily_commission_minor") or 0)
    pending_withdrawals = PayoutRequest.query.filter_by(status="pending").all()
    pending_minor = int(sum(_minor(getattr(row, "amount", 0.0)) for row in pending_withdrawals))
    payout_pressure = float(pending_minor / float(max(1, avg_daily_commission)))
    simulation_30 = run_liquidity_simulation(
        time_horizon_days=30,
        assumed_daily_gmv_minor=int(baseline.get("avg_daily_gmv_minor") or 0),
        assumed_order_count_daily=float(baseline.get("avg_daily_orders") or 0.0),
        withdrawal_rate_pct=float(baseline.get("withdrawal_ratio") or 0.0) * 100.0,
        payout_delay_days=3,
        chargeback_rate_pct=1.5,
        operating_cost_daily_minor=0,
        commission_bps=500,
        scenario="base",
    )
    simulation_90 = run_liquidity_simulation(
        time_horizon_days=90,
        assumed_daily_gmv_minor=int(baseline.get("avg_daily_gmv_minor") or 0),
        assumed_order_count_daily=float(baseline.get("avg_daily_orders") or 0.0),
        withdrawal_rate_pct=float(baseline.get("withdrawal_ratio") or 0.0) * 100.0,
        payout_delay_days=3,
        chargeback_rate_pct=1.5,
        operating_cost_daily_minor=0,
        commission_bps=500,
        scenario="base",
    )
    liquidity = {
        "withdrawal_ratio_30d": float(round(float(baseline.get("withdrawal_ratio") or 0.0), 6)),
        "float_min_30d_minor": int(simulation_30.get("min_cash_balance_minor") or 0),
        "payout_pressure": float(round(payout_pressure, 6)),
        "days_to_negative": simulation_90.get("days_to_negative"),
        "pending_withdrawals_minor": int(max(0, pending_minor)),
        "avg_daily_commission_minor": int(max(0, avg_daily_commission)),
    }

    segments = _segment_map_to_jsonable(current, previous, liquidity)
    totals = defaultdict(int)
    for row in segments:
        totals["order_count"] += int(row.get("order_count") or 0)
        totals["gmv_minor"] += int(row.get("gmv_minor") or 0)

    return {
        "window_days": int(window),
        "generated_at": now.isoformat(),
        "totals": {
            "order_count": int(totals["order_count"]),
            "gmv_minor": int(totals["gmv_minor"]),
            "segments_count": int(len(segments)),
        },
        "liquidity": liquidity,
        "segments": segments,
    }


def compute_snapshot_hash(*, window_days: int, metrics: dict) -> str:
    payload = json.dumps(
        {"window_days": int(window_days), "metrics": metrics},
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
