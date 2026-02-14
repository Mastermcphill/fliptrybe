from __future__ import annotations

from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP

from app.extensions import db
from app.models import Listing, Order, PricingBenchmark, Shortlet, ShortletBooking


PAID_ORDER_STATES = (
    "paid",
    "merchant_accepted",
    "driver_assigned",
    "picked_up",
    "delivered",
    "completed",
)

CONDITION_ADJUSTMENTS_PCT = {
    "new": 10,
    "fair": 0,
    "used": -8,
}


def _to_minor(amount) -> int:
    try:
        value = Decimal(str(amount or 0))
    except Exception:
        value = Decimal("0")
    return int((value * Decimal("100")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _minor_naira(amount_minor: int) -> str:
    try:
        return f"₦{int(amount_minor or 0) / 100:,.0f}"
    except Exception:
        return "₦0"


def _norm(value: str | None) -> str:
    return (value or "").strip().lower()


def _contains_item_type(*, item_type: str, title: str, category: str, description: str) -> bool:
    needle = _norm(item_type)
    if not needle:
        return True
    hay = " ".join([_norm(title), _norm(category), _norm(description)])
    return needle in hay


def _percentile(values: list[int], ratio: float) -> int:
    if not values:
        return 0
    ordered = sorted(int(v) for v in values if int(v) >= 0)
    if not ordered:
        return 0
    if ratio <= 0:
        return int(ordered[0])
    if ratio >= 1:
        return int(ordered[-1])
    idx = int(round((len(ordered) - 1) * ratio))
    idx = max(0, min(idx, len(ordered) - 1))
    return int(ordered[idx])


def _condition_pct(value: str | None) -> int:
    text = _norm(value)
    if "new" in text:
        return CONDITION_ADJUSTMENTS_PCT["new"]
    if "fair" in text:
        return CONDITION_ADJUSTMENTS_PCT["fair"]
    if "used" in text:
        return CONDITION_ADJUSTMENTS_PCT["used"]
    return 0


def _demand_adjustment_pct(*, category: str, city: str) -> int:
    now = datetime.utcnow()
    recent_from = now - timedelta(days=30)
    prior_from = now - timedelta(days=60)
    city_norm = _norm(city)
    cat = _norm(category)

    if cat == "shortlet":
        recent = ShortletBooking.query.filter(
            ShortletBooking.created_at >= recent_from,
            ShortletBooking.payment_status == "paid",
        ).count()
        prior = ShortletBooking.query.filter(
            ShortletBooking.created_at >= prior_from,
            ShortletBooking.created_at < recent_from,
            ShortletBooking.payment_status == "paid",
        ).count()
    else:
        recent_query = Order.query.filter(Order.created_at >= recent_from, Order.status.in_(PAID_ORDER_STATES))
        prior_query = Order.query.filter(
            Order.created_at >= prior_from,
            Order.created_at < recent_from,
            Order.status.in_(PAID_ORDER_STATES),
        )
        if city_norm:
            listing_ids = [
                int(row.id)
                for row in Listing.query.filter(Listing.city.ilike(city_norm)).with_entities(Listing.id).all()
            ]
            if listing_ids:
                recent_query = recent_query.filter(Order.listing_id.in_(listing_ids))
                prior_query = prior_query.filter(Order.listing_id.in_(listing_ids))
        recent = recent_query.count()
        prior = prior_query.count()
    if prior <= 0:
        return 0
    growth = (recent - prior) / float(prior)
    return 5 if growth >= 0.2 else 0


def _collect_declutter_samples(*, city: str, item_type: str) -> list[int]:
    out: list[int] = []
    city_norm = _norm(city)
    orders = (
        Order.query.filter(Order.status.in_(PAID_ORDER_STATES))
        .order_by(Order.created_at.desc())
        .limit(2500)
        .all()
    )
    listing_ids = [int(o.listing_id) for o in orders if o.listing_id is not None]
    listing_map = {}
    if listing_ids:
        rows = Listing.query.filter(Listing.id.in_(listing_ids)).all()
        listing_map = {int(row.id): row for row in rows}

    for order in orders:
        listing = listing_map.get(int(order.listing_id or 0))
        if city_norm and listing and _norm(getattr(listing, "city", "")) != city_norm:
            continue
        title = getattr(listing, "title", "") if listing else ""
        category = getattr(listing, "category", "") if listing else ""
        desc = getattr(listing, "description", "") if listing else ""
        if not _contains_item_type(item_type=item_type, title=title, category=category, description=desc):
            continue
        sale_charge_minor = int(order.sale_seller_minor or 0) + int(order.sale_fee_minor or 0)
        if sale_charge_minor <= 0:
            sale_charge_minor = _to_minor(getattr(order, "amount", 0.0))
        if sale_charge_minor > 0:
            out.append(int(sale_charge_minor))

    if len(out) >= 20:
        return out

    listings = Listing.query.order_by(Listing.date_posted.desc()).limit(2500).all()
    for row in listings:
        if city_norm and _norm(getattr(row, "city", "")) != city_norm:
            continue
        if not _contains_item_type(
            item_type=item_type,
            title=getattr(row, "title", ""),
            category=getattr(row, "category", ""),
            description=getattr(row, "description", ""),
        ):
            continue
        minor = _to_minor(getattr(row, "price", 0.0))
        if minor > 0:
            out.append(minor)
    return out


def _collect_shortlet_samples(*, city: str, item_type: str) -> list[int]:
    out: list[int] = []
    city_norm = _norm(city)
    bookings = (
        ShortletBooking.query.filter(ShortletBooking.payment_status == "paid")
        .order_by(ShortletBooking.created_at.desc())
        .limit(2500)
        .all()
    )
    shortlet_ids = [int(row.shortlet_id) for row in bookings if row.shortlet_id is not None]
    shortlet_map = {}
    if shortlet_ids:
        rows = Shortlet.query.filter(Shortlet.id.in_(shortlet_ids)).all()
        shortlet_map = {int(row.id): row for row in rows}

    for booking in bookings:
        shortlet = shortlet_map.get(int(booking.shortlet_id or 0))
        if city_norm and shortlet and _norm(getattr(shortlet, "city", "")) != city_norm:
            continue
        title = getattr(shortlet, "title", "") if shortlet else ""
        category = getattr(shortlet, "property_type", "") if shortlet else ""
        desc = getattr(shortlet, "description", "") if shortlet else ""
        if not _contains_item_type(item_type=item_type, title=title, category=category, description=desc):
            continue
        total_minor = int(booking.amount_minor or 0)
        if total_minor <= 0:
            total_minor = _to_minor(getattr(booking, "total_amount", 0.0))
        nights = max(1, int(getattr(booking, "nights", 1) or 1))
        nightly_minor = int(round(total_minor / nights))
        if nightly_minor > 0:
            out.append(nightly_minor)

    if len(out) >= 20:
        return out

    shortlets = Shortlet.query.order_by(Shortlet.created_at.desc()).limit(2500).all()
    for row in shortlets:
        if city_norm and _norm(getattr(row, "city", "")) != city_norm:
            continue
        if not _contains_item_type(
            item_type=item_type,
            title=getattr(row, "title", ""),
            category=getattr(row, "property_type", ""),
            description=getattr(row, "description", ""),
        ):
            continue
        minor = _to_minor(getattr(row, "nightly_price", 0.0))
        if minor > 0:
            out.append(minor)
    return out


def _collect_samples(*, category: str, city: str, item_type: str) -> list[int]:
    if _norm(category) == "shortlet":
        return _collect_shortlet_samples(city=city, item_type=item_type)
    return _collect_declutter_samples(city=city, item_type=item_type)


def _confidence(sample_size: int) -> str:
    if sample_size >= 40:
        return "high"
    if sample_size >= 12:
        return "medium"
    return "low"


def refresh_benchmark_from_samples(*, category: str, city: str, item_type: str, samples: list[int]) -> PricingBenchmark:
    city_value = (city or "").strip() or "Nigeria"
    item_value = (item_type or "").strip() or None
    row = PricingBenchmark.query.filter_by(
        category=_norm(category) or "declutter",
        city=city_value,
        item_type=item_value,
    ).first()
    if not row:
        row = PricingBenchmark(category=_norm(category) or "declutter", city=city_value, item_type=item_value)
        db.session.add(row)

    row.p25_minor = _percentile(samples, 0.25)
    row.p50_minor = _percentile(samples, 0.50)
    row.p75_minor = _percentile(samples, 0.75)
    row.sample_size = int(len(samples))
    row.updated_at = datetime.utcnow()
    db.session.commit()
    return row


def suggest_price(
    *,
    category: str,
    city: str,
    item_type: str,
    condition: str,
    current_price_minor: int,
    duration_nights: int | None = None,
) -> dict:
    cat = _norm(category)
    cat = "shortlet" if cat == "shortlet" else "declutter"
    city_value = (city or "").strip() or "Lagos"
    item_value = (item_type or "").strip()
    samples = _collect_samples(category=cat, city=city_value, item_type=item_value)
    if len(samples) < 8 and item_value:
        # fallback to broader city/category
        samples = _collect_samples(category=cat, city=city_value, item_type="")
    if len(samples) < 8:
        # final fallback to overall category
        samples = _collect_samples(category=cat, city="", item_type="")

    benchmark = refresh_benchmark_from_samples(
        category=cat,
        city=city_value,
        item_type=item_value,
        samples=samples,
    )

    base_minor = int(benchmark.p50_minor or 0)
    condition_pct = _condition_pct(condition)
    demand_pct = _demand_adjustment_pct(category=cat, city=city_value)
    total_pct = condition_pct + demand_pct
    multiplier = Decimal("1") + (Decimal(total_pct) / Decimal("100"))
    suggested_minor = int((Decimal(base_minor) * multiplier).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    low_minor = int((Decimal(int(benchmark.p25_minor or 0)) * multiplier).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    high_minor = int((Decimal(int(benchmark.p75_minor or 0)) * multiplier).quantize(Decimal("1"), rounding=ROUND_HALF_UP))

    explanation = [
        f"Based on {city_value} median for {(item_value or cat)}: {_minor_naira(base_minor)}",
    ]
    if condition_pct != 0:
        sign = "+" if condition_pct > 0 else ""
        explanation.append(f"Adjusted {sign}{condition_pct}% for {(_norm(condition) or 'standard')} condition")
    if demand_pct > 0:
        explanation.append(f"Adjusted +{demand_pct}% for higher recent demand")
    if current_price_minor > 0:
        if current_price_minor < int(benchmark.p25_minor or 0):
            explanation.append("Current price is below market p25; consider moving up for margin protection")
        elif current_price_minor > int(benchmark.p75_minor or 0):
            explanation.append("Current price is above market p75; consider lowering for faster conversion")
        else:
            explanation.append("Current price sits inside market range")
    if cat == "shortlet" and duration_nights and duration_nights > 1:
        explanation.append(f"Quote generated per-night; multiply by {int(duration_nights)} nights for stay totals")

    return {
        "suggested_price_minor": int(max(0, suggested_minor)),
        "range_minor": {
            "low": int(max(0, low_minor)),
            "high": int(max(0, high_minor)),
        },
        "confidence": _confidence(int(benchmark.sample_size or 0)),
        "explanation": explanation,
        "benchmarks": {
            "p25": int(benchmark.p25_minor or 0),
            "p50": int(benchmark.p50_minor or 0),
            "p75": int(benchmark.p75_minor or 0),
            "sample_size": int(benchmark.sample_size or 0),
            "updated_at": benchmark.updated_at.isoformat() if benchmark.updated_at else None,
        },
    }
