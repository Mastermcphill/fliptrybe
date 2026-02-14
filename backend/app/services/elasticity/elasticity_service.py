from __future__ import annotations

import hashlib
import json
import math
from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP

from app.extensions import db
from app.models import ElasticitySnapshot, Listing, Order, Shortlet, ShortletBooking, User
from app.models.strategic_intelligence import strategic_json_dump


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


def _norm(value: str | None) -> str:
    text = (value or "").strip().lower()
    return text or "all"


def _as_seller_type(role: str | None) -> str:
    return "merchant" if (role or "").strip().lower() == "merchant" else "user"


def _seller_filter_ok(expected: str, actual: str) -> bool:
    if expected == "all":
        return True
    return expected == actual


def _city_filter_ok(expected: str, actual: str) -> bool:
    if expected == "all":
        return True
    return _norm(actual) == expected


def _price_sensitivity(coefficient: float) -> str:
    magnitude = abs(float(coefficient or 0.0))
    if magnitude < 0.4:
        return "low"
    if magnitude < 0.9:
        return "medium"
    return "high"


def _confidence(sample_size: int, points_count: int, r2: float) -> str:
    score = 0
    if sample_size >= 40:
        score += 1
    if sample_size >= 120:
        score += 1
    if points_count >= 3:
        score += 1
    if points_count >= 5:
        score += 1
    if abs(r2) >= 0.15:
        score += 1
    if abs(r2) >= 0.3:
        score += 1
    if score >= 5:
        return "high"
    if score >= 3:
        return "medium"
    return "low"


def _recommended_shift_pct(coefficient: float, confidence: str) -> float:
    coef = float(coefficient or 0.0)
    if confidence == "low":
        return 0.0
    if coef <= -1.1:
        return -4.0
    if coef <= -0.75:
        return -2.5
    if coef <= -0.4:
        return -1.0
    if coef >= 0.35:
        return 2.0
    return 0.0


def _pearson(xs: list[float], ys: list[float]) -> float:
    if len(xs) != len(ys) or len(xs) < 2:
        return 0.0
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    vx = sum((x - mx) ** 2 for x in xs)
    vy = sum((y - my) ** 2 for y in ys)
    if vx <= 0 or vy <= 0:
        return 0.0
    return float(cov / math.sqrt(vx * vy))


def _linear_regression(xs: list[float], ys: list[float]) -> tuple[float, float, float]:
    if len(xs) != len(ys) or len(xs) < 2:
        return (0.0, 0.0, 0.0)
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx <= 0:
        return (0.0, my, 0.0)
    slope = sxy / sxx
    intercept = my - (slope * mx)
    ss_tot = sum((y - my) ** 2 for y in ys)
    ss_res = sum((y - (slope * x + intercept)) ** 2 for x, y in zip(xs, ys))
    r2 = 1.0 - (ss_res / ss_tot) if ss_tot > 0 else 0.0
    return (float(slope), float(intercept), float(r2))


def _bucket_edges(values: list[int], bucket_count: int = 5) -> list[int]:
    normalized = sorted(int(v) for v in values if int(v) > 0)
    if not normalized:
        return [0, 1]
    lo = int(normalized[0])
    hi = int(normalized[-1])
    if lo == hi:
        return [lo, hi + 1]
    bucket_count = max(3, min(int(bucket_count), 8))
    width = max(1, int(math.ceil((hi - lo) / float(bucket_count))))
    edges = [lo]
    for _ in range(bucket_count - 1):
        edges.append(edges[-1] + width)
    edges.append(hi + 1)
    return edges


def _bucket_index(value: int, edges: list[int]) -> int:
    if len(edges) < 2:
        return 0
    val = int(value or 0)
    for idx in range(len(edges) - 1):
        low = edges[idx]
        high = edges[idx + 1]
        if idx == len(edges) - 2:
            if val >= low and val <= high:
                return idx
        if val >= low and val < high:
            return idx
    return max(0, len(edges) - 2)


def _build_hash_key(segment: dict, payload: dict) -> str:
    raw = json.dumps({"segment": segment, "payload": payload}, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _user_roles_map() -> dict[int, str]:
    rows = User.query.with_entities(User.id, User.role).all()
    return {int(uid): (role or "buyer").strip().lower() for uid, role in rows}


def _collect_declutter_data(*, city: str, seller_type: str, since: datetime) -> tuple[list[dict], list[int]]:
    roles = _user_roles_map()
    orders = Order.query.filter(Order.created_at >= since, Order.status.in_(PAID_ORDER_STATES)).all()
    listing_ids = [int(row.listing_id) for row in orders if getattr(row, "listing_id", None)]
    listings = Listing.query.filter(Listing.id.in_(listing_ids)).all() if listing_ids else []
    listing_map = {int(row.id): row for row in listings}
    tx_rows: list[dict] = []

    for row in orders:
        listing = listing_map.get(int(row.listing_id or 0))
        if not listing:
            continue
        seller_id = int(getattr(listing, "user_id", 0) or getattr(row, "merchant_id", 0) or 0)
        seller_role = _as_seller_type(roles.get(seller_id))
        if not _seller_filter_ok(seller_type, seller_role):
            continue
        if not _city_filter_ok(city, getattr(listing, "city", None)):
            continue
        charge_minor = int(row.sale_seller_minor or 0) + int(row.sale_fee_minor or 0)
        if charge_minor <= 0:
            charge_minor = _to_minor(getattr(row, "total_price", None) or getattr(row, "amount", 0.0))
        if charge_minor <= 0:
            continue
        fee_minor = int(row.sale_fee_minor or 0)
        bps = int(round((fee_minor * 10000.0) / charge_minor)) if charge_minor > 0 else 500
        tx_rows.append(
            {
                "price_minor": int(charge_minor),
                "gmv_minor": int(charge_minor),
                "commission_bps": int(max(0, bps)),
            }
        )

    listing_rows = Listing.query.filter(Listing.is_active == True).all()  # noqa: E712
    listing_prices: list[int] = []
    for row in listing_rows:
        role = _as_seller_type(roles.get(int(getattr(row, "user_id", 0) or 0)))
        if not _seller_filter_ok(seller_type, role):
            continue
        if not _city_filter_ok(city, getattr(row, "city", None)):
            continue
        price_minor = _to_minor(getattr(row, "final_price", None) or getattr(row, "price", 0.0))
        if price_minor > 0:
            listing_prices.append(int(price_minor))
    return tx_rows, listing_prices


def _collect_shortlet_data(*, city: str, seller_type: str, since: datetime) -> tuple[list[dict], list[int]]:
    roles = _user_roles_map()
    bookings = ShortletBooking.query.filter(
        ShortletBooking.created_at >= since,
        ShortletBooking.payment_status.in_(PAID_BOOKING_STATES),
    ).all()
    shortlet_ids = [int(row.shortlet_id) for row in bookings if getattr(row, "shortlet_id", None)]
    shortlets = Shortlet.query.filter(Shortlet.id.in_(shortlet_ids)).all() if shortlet_ids else []
    shortlet_map = {int(row.id): row for row in shortlets}
    tx_rows: list[dict] = []

    for row in bookings:
        shortlet = shortlet_map.get(int(row.shortlet_id or 0))
        if not shortlet:
            continue
        owner_id = int(getattr(shortlet, "owner_id", 0) or 0)
        role = _as_seller_type(roles.get(owner_id))
        if not _seller_filter_ok(seller_type, role):
            continue
        if not _city_filter_ok(city, getattr(shortlet, "city", None)):
            continue
        nights = max(1, int(getattr(row, "nights", 1) or 1))
        total_minor = int(getattr(row, "amount_minor", 0) or 0)
        if total_minor <= 0:
            total_minor = _to_minor(getattr(row, "total_amount", 0.0))
        if total_minor <= 0:
            continue
        nightly_minor = int(round(total_minor / float(nights)))
        tx_rows.append(
            {
                "price_minor": int(max(1, nightly_minor)),
                "gmv_minor": int(max(1, total_minor)),
                "commission_bps": 500,
            }
        )

    listing_prices: list[int] = []
    for row in Shortlet.query.all():
        owner_id = int(getattr(row, "owner_id", 0) or 0)
        role = _as_seller_type(roles.get(owner_id))
        if not _seller_filter_ok(seller_type, role):
            continue
        if not _city_filter_ok(city, getattr(row, "city", None)):
            continue
        nightly_minor = _to_minor(getattr(row, "final_price", None) or getattr(row, "nightly_price", 0.0))
        if nightly_minor > 0:
            listing_prices.append(int(nightly_minor))
    return tx_rows, listing_prices


def compute_segment_elasticity(
    *,
    category: str,
    city: str = "all",
    seller_type: str = "all",
    window_days: int = 90,
    persist_snapshot: bool = True,
) -> dict:
    segment_category = "shortlet" if _norm(category) == "shortlet" else "declutter"
    segment_city = _norm(city)
    segment_seller_type = _norm(seller_type)
    if segment_seller_type not in ("all", "user", "merchant"):
        segment_seller_type = "all"
    window = max(7, min(int(window_days or 90), 365))
    since = datetime.utcnow() - timedelta(days=window)

    if segment_category == "shortlet":
        transactions, listing_prices = _collect_shortlet_data(city=segment_city, seller_type=segment_seller_type, since=since)
    else:
        transactions, listing_prices = _collect_declutter_data(city=segment_city, seller_type=segment_seller_type, since=since)

    tx_prices = [int(row["price_minor"]) for row in transactions if int(row.get("price_minor", 0)) > 0]
    all_prices = tx_prices + listing_prices
    edges = _bucket_edges(all_prices, bucket_count=5)
    bucket_count = max(1, len(edges) - 1)
    buckets = [
        {
            "bucket_index": idx,
            "price_low_minor": int(edges[idx]),
            "price_high_minor": int(edges[idx + 1]),
            "price_mid_minor": int(round((edges[idx] + edges[idx + 1]) / 2.0)),
            "listings_count": 0,
            "orders_count": 0,
            "gmv_minor": 0,
            "avg_commission_bps": 0,
            "_bps_sum": 0,
        }
        for idx in range(bucket_count)
    ]

    for value in listing_prices:
        idx = _bucket_index(value, edges)
        buckets[idx]["listings_count"] += 1

    for row in transactions:
        idx = _bucket_index(int(row["price_minor"]), edges)
        buckets[idx]["orders_count"] += 1
        buckets[idx]["gmv_minor"] += int(row["gmv_minor"])
        buckets[idx]["_bps_sum"] += int(row["commission_bps"])

    conversion_points_x: list[float] = []
    conversion_points_y: list[float] = []
    distribution = []
    gmv_curve = []
    conversion_curve = []

    for bucket in buckets:
        listings_count = int(bucket["listings_count"] or 0)
        orders_count = int(bucket["orders_count"] or 0)
        if orders_count > 0:
            bucket["avg_commission_bps"] = int(round(bucket["_bps_sum"] / float(orders_count)))
        conversion = float(orders_count / listings_count) if listings_count > 0 else float(orders_count)
        bucket["conversion_proxy"] = round(conversion, 6)
        distribution.append(
            {
                "bucket_index": int(bucket["bucket_index"]),
                "price_low_minor": int(bucket["price_low_minor"]),
                "price_high_minor": int(bucket["price_high_minor"]),
                "listings_count": int(listings_count),
                "orders_count": int(orders_count),
                "conversion_proxy": float(bucket["conversion_proxy"]),
            }
        )
        gmv_curve.append(
            {
                "price_mid_minor": int(bucket["price_mid_minor"]),
                "gmv_minor": int(bucket["gmv_minor"]),
                "orders_count": int(orders_count),
            }
        )
        conversion_curve.append(
            {
                "price_mid_minor": int(bucket["price_mid_minor"]),
                "conversion_proxy": float(bucket["conversion_proxy"]),
                "avg_commission_bps": int(bucket["avg_commission_bps"]),
            }
        )
        if bucket["price_mid_minor"] > 0 and conversion > 0:
            conversion_points_x.append(float(math.log(max(1.0, float(bucket["price_mid_minor"])))))
            conversion_points_y.append(float(math.log(max(1e-6, conversion))))

    coefficient = -0.4
    intercept = 0.0
    r2 = 0.0
    if len(conversion_points_x) >= 2:
        slope, intercept, r2 = _linear_regression(conversion_points_x, conversion_points_y)
        coefficient = float(round(slope, 4))
    else:
        if len(transactions) >= 60:
            coefficient = -0.55
        elif len(transactions) >= 20:
            coefficient = -0.4
        else:
            coefficient = -0.3

    commission_corr = _pearson(
        [float(row["commission_bps"]) for row in transactions],
        [float(row["gmv_minor"]) for row in transactions],
    )
    confidence = _confidence(len(transactions), len(conversion_points_x), r2)
    recommended_shift = _recommended_shift_pct(coefficient, confidence)
    sensitivity = _price_sensitivity(coefficient)

    summary = {
        "segment": {
            "category": segment_category,
            "city": segment_city,
            "seller_type": segment_seller_type,
            "window_days": int(window),
        },
        "sample_size": int(len(transactions)),
        "elasticity_coefficient": float(coefficient),
        "price_sensitivity": sensitivity,
        "recommended_price_shift_pct": float(recommended_shift),
        "confidence": confidence,
        "model_debug": {
            "regression_intercept": float(round(intercept, 6)),
            "regression_r2": float(round(r2, 6)),
            "usable_points": int(len(conversion_points_x)),
            "commission_bps_gmv_correlation": float(round(commission_corr, 6)),
        },
        "price_bucket_distributions": distribution,
        "conversion_curve": conversion_curve,
        "gmv_price_curve": gmv_curve,
        "explanation": [
            f"Computed from {len(transactions)} paid transactions in the last {window} days.",
            f"Elasticity coefficient {coefficient:.3f} ({sensitivity} sensitivity).",
            f"Suggested safe price shift: {recommended_shift:+.1f}%.",
        ],
        "generated_at": datetime.utcnow().isoformat(),
    }

    segment_key = {
        "category": segment_category,
        "city": segment_city,
        "seller_type": segment_seller_type,
        "window_days": int(window),
    }
    hash_payload = {
        "segment": segment_key,
        "sample_size": int(len(transactions)),
        "elasticity_coefficient": float(coefficient),
        "price_sensitivity": sensitivity,
        "recommended_price_shift_pct": float(recommended_shift),
        "confidence": confidence,
        "price_bucket_distributions": distribution,
        "conversion_curve": conversion_curve,
        "gmv_price_curve": gmv_curve,
        "commission_bps_gmv_correlation": float(round(commission_corr, 6)),
    }
    hash_key = _build_hash_key(segment_key, hash_payload)
    snapshot = ElasticitySnapshot.query.filter_by(hash_key=hash_key).first()
    if persist_snapshot and snapshot is None:
        snapshot = ElasticitySnapshot(
            category=segment_category,
            city=segment_city,
            seller_type=segment_seller_type,
            window_days=int(window),
            sample_size=int(len(transactions)),
            elasticity_coefficient=float(coefficient),
            confidence=confidence,
            recommendation_shift_pct=float(recommended_shift),
            metrics_json=strategic_json_dump(summary),
            hash_key=hash_key,
            created_at=datetime.utcnow(),
        )
        db.session.add(snapshot)
        db.session.commit()
    elif snapshot is not None:
        summary["snapshot_id"] = int(snapshot.id)

    if snapshot is not None:
        summary["snapshot_id"] = int(snapshot.id)
        summary["idempotent"] = True
    else:
        summary["idempotent"] = False
    summary["hash_key"] = hash_key
    return summary


def segment_elasticity_coefficient(*, category: str, city: str = "all", seller_type: str = "all") -> dict:
    result = compute_segment_elasticity(
        category=category,
        city=city,
        seller_type=seller_type,
        window_days=90,
        persist_snapshot=True,
    )
    return {
        "coefficient": float(result.get("elasticity_coefficient") or -0.4),
        "confidence": (result.get("confidence") or "low"),
        "sensitivity": (result.get("price_sensitivity") or "low"),
        "recommended_shift_pct": float(result.get("recommended_price_shift_pct") or 0.0),
    }


def list_recent_elasticity_snapshots(*, limit: int = 30) -> list[dict]:
    rows = (
        ElasticitySnapshot.query.order_by(ElasticitySnapshot.created_at.desc(), ElasticitySnapshot.id.desc())
        .limit(max(1, min(int(limit), 200)))
        .all()
    )
    return [row.to_dict() for row in rows]
