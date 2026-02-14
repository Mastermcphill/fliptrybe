from __future__ import annotations

from collections import Counter, defaultdict
from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP

from app.models import Listing, Order, PayoutRequest, Shortlet, ShortletBooking


PAID_ORDER_STATES = (
    "paid",
    "merchant_accepted",
    "driver_assigned",
    "picked_up",
    "delivered",
    "completed",
)

PAID_BOOKING_STATES = ("paid", "confirmed")


def _to_minor(amount) -> int:
    try:
        value = Decimal(str(amount or 0))
    except Exception:
        value = Decimal("0")
    return int((value * Decimal("100")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _norm_city(value: str | None) -> str:
    text = (value or "").strip()
    return text if text else "Unknown"


def _user_city_map() -> dict[int, str]:
    counts: dict[int, Counter[str]] = defaultdict(Counter)
    for row in Listing.query.all():
        uid = int(getattr(row, "user_id", 0) or 0)
        if uid <= 0:
            continue
        counts[uid][_norm_city(getattr(row, "city", None))] += 1
    for row in Shortlet.query.all():
        uid = int(getattr(row, "owner_id", 0) or 0)
        if uid <= 0:
            continue
        counts[uid][_norm_city(getattr(row, "city", None))] += 1
    out: dict[int, str] = {}
    for user_id, counter in counts.items():
        if not counter:
            continue
        out[user_id] = counter.most_common(1)[0][0]
    return out


def city_liquidity_snapshot(*, window_days: int = 30) -> dict:
    now = datetime.utcnow()
    since = now - timedelta(days=max(7, min(int(window_days or 30), 120)))
    user_city = _user_city_map()
    metrics: dict[str, dict] = defaultdict(
        lambda: {
            "city": "",
            "gmv_minor": 0,
            "commission_revenue_minor": 0,
            "payouts_minor": 0,
            "float_minor": 0,
            "payout_lag_days_avg": 0.0,
            "_lag_sum": 0.0,
            "_lag_count": 0,
        }
    )

    orders = Order.query.filter(Order.created_at >= since, Order.status.in_(PAID_ORDER_STATES)).all()
    listing_ids = [int(row.listing_id) for row in orders if getattr(row, "listing_id", None)]
    listings = Listing.query.filter(Listing.id.in_(listing_ids)).all() if listing_ids else []
    listing_map = {int(row.id): row for row in listings}
    for row in orders:
        listing = listing_map.get(int(row.listing_id or 0))
        city = _norm_city(getattr(listing, "city", None))
        bucket = metrics[city]
        bucket["city"] = city
        order_gmv = _to_minor(getattr(row, "total_price", None) or getattr(row, "amount", 0.0))
        bucket["gmv_minor"] += int(max(0, order_gmv))
        bucket["commission_revenue_minor"] += int(
            max(
                0,
                int(getattr(row, "sale_platform_minor", 0) or 0)
                + int(getattr(row, "delivery_platform_minor", 0) or 0)
                + int(getattr(row, "inspection_platform_minor", 0) or 0),
            )
        )

    bookings = ShortletBooking.query.filter(
        ShortletBooking.created_at >= since,
        ShortletBooking.payment_status.in_(PAID_BOOKING_STATES),
    ).all()
    shortlet_ids = [int(row.shortlet_id) for row in bookings if getattr(row, "shortlet_id", None)]
    shortlets = Shortlet.query.filter(Shortlet.id.in_(shortlet_ids)).all() if shortlet_ids else []
    shortlet_map = {int(row.id): row for row in shortlets}
    for row in bookings:
        shortlet = shortlet_map.get(int(row.shortlet_id or 0))
        city = _norm_city(getattr(shortlet, "city", None))
        bucket = metrics[city]
        bucket["city"] = city
        gmv_minor = int(getattr(row, "amount_minor", 0) or 0)
        if gmv_minor <= 0:
            gmv_minor = _to_minor(getattr(row, "total_amount", 0.0))
        bucket["gmv_minor"] += int(max(0, gmv_minor))
        bucket["commission_revenue_minor"] += int(round(max(0, gmv_minor) * 0.05))

    payouts = PayoutRequest.query.filter(PayoutRequest.created_at >= since).all()
    for row in payouts:
        city = _norm_city(user_city.get(int(getattr(row, "user_id", 0) or 0)))
        bucket = metrics[city]
        bucket["city"] = city
        payout_minor = _to_minor(getattr(row, "amount", 0.0))
        bucket["payouts_minor"] += int(max(0, payout_minor))
        if getattr(row, "status", "").strip().lower() == "paid":
            created_at = getattr(row, "created_at", None)
            updated_at = getattr(row, "updated_at", None) or created_at
            if created_at and updated_at:
                lag = max(0.0, (updated_at - created_at).total_seconds() / 86400.0)
                bucket["_lag_sum"] += float(lag)
                bucket["_lag_count"] += 1

    rows = []
    for city, bucket in metrics.items():
        gmv = int(bucket["gmv_minor"] or 0)
        commission = int(bucket["commission_revenue_minor"] or 0)
        payouts_minor = int(bucket["payouts_minor"] or 0)
        float_minor = int(commission - payouts_minor)
        withdrawal_ratio = float(payouts_minor / float(gmv)) if gmv > 0 else 0.0
        float_ratio = float(float_minor / float(gmv)) if gmv > 0 else 0.0
        lag_avg = float(bucket["_lag_sum"] / bucket["_lag_count"]) if bucket["_lag_count"] > 0 else 0.0
        rows.append(
            {
                "city": city,
                "gmv_minor": gmv,
                "commission_revenue_minor": commission,
                "payouts_minor": payouts_minor,
                "withdrawal_ratio": round(max(0.0, withdrawal_ratio), 6),
                "float_ratio": round(float_ratio, 6),
                "float_minor": int(float_minor),
                "payout_lag_days": round(max(0.0, lag_avg), 4),
            }
        )

    rows.sort(key=lambda r: (r["gmv_minor"], r["commission_revenue_minor"]), reverse=True)
    stressed = [row for row in rows if row["float_ratio"] < -0.02 and row["gmv_minor"] > 0]
    surplus = [row for row in rows if row["float_ratio"] > 0.04 and row["gmv_minor"] > 0]
    return {
        "ok": True,
        "window_days": int(max(7, min(int(window_days or 30), 120))),
        "generated_at": now.isoformat(),
        "cities": rows,
        "risk_flags": [
            "CROSS_MARKET_LIQUIDITY_RISK"
            for _ in stressed
            if surplus
        ][:1],
        "stressed_cities": [row["city"] for row in stressed],
        "surplus_cities": [row["city"] for row in surplus],
    }


def simulate_cross_market_balance(
    *,
    time_horizon_days: int = 90,
    commission_shift_city: str = "",
    commission_shift_bps: int = 0,
    promo_city: str = "",
    promo_discount_bps: int = 0,
    payout_delay_adjustment_days: int = 0,
) -> dict:
    horizon = max(7, min(int(time_horizon_days or 90), 365))
    shift_city = _norm_city(commission_shift_city) if (commission_shift_city or "").strip() else ""
    promo_target = _norm_city(promo_city) if (promo_city or "").strip() else ""
    shift_bps = max(-300, min(int(commission_shift_bps or 0), 300))
    promo_bps = max(0, min(int(promo_discount_bps or 0), 300))
    payout_delay_days = max(-7, min(int(payout_delay_adjustment_days or 0), 14))
    baseline = city_liquidity_snapshot(window_days=30)
    city_rows = baseline.get("cities") or []

    results = []
    stressed_after = []
    for row in city_rows:
        city = row.get("city") or "Unknown"
        gmv_minor = int(row.get("gmv_minor") or 0)
        withdrawal_ratio = float(row.get("withdrawal_ratio") or 0.0)
        base_bps = 500
        effective_bps = int(base_bps)
        if shift_city and city.lower() == shift_city.lower():
            effective_bps += shift_bps
        if promo_target and city.lower() == promo_target.lower():
            effective_bps -= promo_bps
        effective_bps = max(0, min(effective_bps, 2000))
        horizon_factor = float(horizon / 30.0)
        projected_commission = int(round(gmv_minor * horizon_factor * (effective_bps / 10000.0)))
        payout_factor = 1.0
        if payout_delay_days != 0:
            payout_factor = max(0.7, min(1.3, 1.0 - (0.03 * payout_delay_days)))
        projected_payouts = int(round(gmv_minor * horizon_factor * withdrawal_ratio * payout_factor))
        projected_float = int(projected_commission - projected_payouts)
        projected_float_ratio = float(projected_float / float(max(1, int(round(gmv_minor * horizon_factor)))))
        if projected_float_ratio < -0.02:
            stressed_after.append(city)
        results.append(
            {
                "city": city,
                "baseline_gmv_minor": gmv_minor,
                "effective_commission_bps": int(effective_bps),
                "projected_commission_minor": int(projected_commission),
                "projected_payouts_minor": int(projected_payouts),
                "projected_float_minor": int(projected_float),
                "projected_float_ratio": round(projected_float_ratio, 6),
            }
        )

    total_float = int(sum(int(row["projected_float_minor"]) for row in results))
    return {
        "ok": True,
        "generated_at": datetime.utcnow().isoformat(),
        "inputs": {
            "time_horizon_days": int(horizon),
            "commission_shift_city": shift_city,
            "commission_shift_bps": int(shift_bps),
            "promo_city": promo_target,
            "promo_discount_bps": int(promo_bps),
            "payout_delay_adjustment_days": int(payout_delay_days),
        },
        "cities": results,
        "summary": {
            "projected_total_float_minor": int(total_float),
            "stressed_cities_after": stressed_after,
            "cross_market_liquidity_risk": bool(len(stressed_after) > 0),
        },
    }
