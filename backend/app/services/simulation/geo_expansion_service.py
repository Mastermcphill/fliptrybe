from __future__ import annotations

from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP

from app.models import Listing, Order, Shortlet, ShortletBooking


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


def _confidence_for_city(target_city: str) -> str:
    city = (target_city or "").strip().lower()
    if not city:
        return "low"
    since = datetime.utcnow() - timedelta(days=90)

    listing_ids = [
        int(row.id)
        for row in Listing.query.filter(Listing.city.ilike(city), Listing.created_at >= since).with_entities(Listing.id).all()
    ]
    order_count = 0
    if listing_ids:
        order_count = (
            Order.query.filter(
                Order.listing_id.in_(listing_ids),
                Order.created_at >= since,
                Order.status.in_(PAID_ORDER_STATES),
            ).count()
        )

    shortlet_ids = [
        int(row.id)
        for row in Shortlet.query.filter(Shortlet.city.ilike(city), Shortlet.created_at >= since).with_entities(Shortlet.id).all()
    ]
    booking_count = 0
    if shortlet_ids:
        booking_count = (
            ShortletBooking.query.filter(
                ShortletBooking.shortlet_id.in_(shortlet_ids),
                ShortletBooking.created_at >= since,
                ShortletBooking.payment_status.in_(PAID_BOOKING_STATES),
            ).count()
        )
    total = int(order_count + booking_count)
    if total >= 120:
        return "high"
    if total >= 35:
        return "medium"
    return "low"


def simulate_geo_expansion(
    *,
    target_city: str,
    assumed_listings: int,
    assumed_daily_gmv_minor: int,
    average_order_value_minor: int,
    marketing_budget_minor: int,
    estimated_commission_bps: int,
    operating_cost_daily_minor: int,
) -> dict:
    days = 180
    city = (target_city or "").strip() or "Unknown"
    listings_count = max(0, int(assumed_listings or 0))
    daily_gmv = max(0, int(assumed_daily_gmv_minor or 0))
    avg_order_value = max(1, int(average_order_value_minor or 1))
    marketing_budget = max(0, int(marketing_budget_minor or 0))
    commission_bps = max(0, min(int(estimated_commission_bps or 500), 3000))
    opex_daily = max(0, int(operating_cost_daily_minor or 0))

    projected_gmv_minor = int(daily_gmv * days)
    projected_commission_minor = int(round(projected_gmv_minor * (commission_bps / 10000.0)))
    projected_operating_minor = int(opex_daily * days)
    total_cost_minor = int(projected_operating_minor + marketing_budget)
    projected_net_minor = int(projected_commission_minor - total_cost_minor)

    projected_orders = int(round(projected_gmv_minor / float(avg_order_value)))
    estimated_new_customers = max(1, int(round(projected_orders * 0.35)))
    cac_minor = int(round(marketing_budget / float(estimated_new_customers)))

    daily_commission_minor = int(round(daily_gmv * (commission_bps / 10000.0)))
    daily_net_after_opex_minor = int(daily_commission_minor - opex_daily)
    if daily_net_after_opex_minor > 0:
        break_even_days = int(round(marketing_budget / float(daily_net_after_opex_minor)))
    else:
        break_even_days = None

    projected_payouts_minor = int(round(projected_gmv_minor * 0.88))
    projected_float_minor = int(projected_commission_minor - projected_payouts_minor)
    liquidity_stress = projected_float_minor < 0

    roi_projection_pct = (
        float((projected_net_minor / float(marketing_budget)) * 100.0) if marketing_budget > 0 else 0.0
    )
    ltv_estimation_minor = int(round(cac_minor * 3.2))

    return {
        "ok": True,
        "generated_at": datetime.utcnow().isoformat(),
        "inputs": {
            "target_city": city,
            "assumed_listings": int(listings_count),
            "assumed_daily_gmv_minor": int(daily_gmv),
            "average_order_value_minor": int(avg_order_value),
            "marketing_budget_minor": int(marketing_budget),
            "estimated_commission_bps": int(commission_bps),
            "operating_cost_daily_minor": int(opex_daily),
        },
        "projected_6_month_gmv_minor": int(projected_gmv_minor),
        "projected_commission_revenue_minor": int(projected_commission_minor),
        "cac_break_even_days": int(break_even_days) if break_even_days is not None else None,
        "liquidity_stress_indicator": bool(liquidity_stress),
        "roi_projection_pct": float(round(roi_projection_pct, 4)),
        "confidence_score": _confidence_for_city(city),
        "unit_economics": {
            "projected_orders": int(projected_orders),
            "estimated_new_customers": int(estimated_new_customers),
            "estimated_cac_minor": int(cac_minor),
            "ltv_estimation_minor": int(ltv_estimation_minor),
            "projected_net_minor": int(projected_net_minor),
            "projected_float_minor": int(projected_float_minor),
        },
    }
