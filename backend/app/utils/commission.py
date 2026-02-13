from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP

SNAPSHOT_VERSION = 1

SALE_RULE_DECLUTTER_500_BPS = "SALE_DECLUTTER_500_BPS"
SALE_RULE_SHORTLET_500_BPS = "SALE_SHORTLET_500_BPS"
DELIVERY_SPLIT_RULE_V1 = "DELIVERY_SPLIT_90_10_V1"
INSPECTION_SPLIT_RULE_V1 = "INSPECTION_SPLIT_90_10_V1"
TOP_TIER_INCENTIVE_RULE_V1 = "TOP_TIER_11_13_V1"

SALE_FEE_BPS_DECLUTTER = 500
SALE_FEE_BPS_SHORTLET = 500
DELIVERY_ACTOR_BPS = 9000
DELIVERY_PLATFORM_BPS = 1000
INSPECTION_ACTOR_BPS = 9000
INSPECTION_PLATFORM_BPS = 1000
TOP_TIER_INCENTIVE_NUM = 11
TOP_TIER_INCENTIVE_DEN = 13


def _clamp_minor(value: int | float | Decimal | None) -> int:
    try:
        parsed = int(value or 0)
    except Exception:
        parsed = 0
    return parsed if parsed > 0 else 0


def money_major_to_minor(amount: float | Decimal | int | None) -> int:
    try:
        parsed = Decimal(str(amount or 0))
    except Exception:
        parsed = Decimal("0")
    minor = (parsed * Decimal("100")).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    return _clamp_minor(int(minor))


def money_minor_to_major(minor: int | float | Decimal | None) -> float:
    try:
        parsed = Decimal(int(minor or 0))
    except Exception:
        parsed = Decimal("0")
    return float((parsed / Decimal("100")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def _bps_minor_half_up(amount_minor: int, bps: int) -> int:
    amt = Decimal(_clamp_minor(amount_minor))
    rate = Decimal(int(max(0, bps)))
    raw = (amt * rate) / Decimal("10000")
    return _clamp_minor(int(raw.quantize(Decimal("1"), rounding=ROUND_HALF_UP)))


def _split_minor(total_minor: int, actor_bps: int, platform_bps: int) -> tuple[int, int]:
    total = _clamp_minor(total_minor)
    if total <= 0:
        return 0, 0
    platform_minor = _bps_minor_half_up(total, platform_bps)
    actor_minor = total - platform_minor
    if actor_minor < 0:
        actor_minor = 0
    return int(actor_minor), int(platform_minor)


def compute_order_commissions_minor(
    *,
    sale_kind: str,
    sale_charge_minor: int,
    delivery_minor: int,
    inspection_minor: int,
    is_top_tier: bool,
) -> dict:
    kind = (sale_kind or "declutter").strip().lower()
    if kind not in ("declutter", "shortlet"):
        kind = "declutter"

    sale_charge_minor = _clamp_minor(sale_charge_minor)
    delivery_minor = _clamp_minor(delivery_minor)
    inspection_minor = _clamp_minor(inspection_minor)
    is_top_tier_flag = bool(is_top_tier)

    sale_bps = SALE_FEE_BPS_SHORTLET if kind == "shortlet" else SALE_FEE_BPS_DECLUTTER
    sale_rule = SALE_RULE_SHORTLET_500_BPS if kind == "shortlet" else SALE_RULE_DECLUTTER_500_BPS

    sale_fee_minor = _bps_minor_half_up(sale_charge_minor, sale_bps)
    sale_seller_minor = sale_charge_minor - sale_fee_minor
    if sale_seller_minor < 0:
        sale_seller_minor = 0

    sale_top_tier_incentive_minor = 0
    sale_platform_minor = sale_fee_minor
    if sale_fee_minor > 0 and is_top_tier_flag:
        raw = (Decimal(sale_fee_minor) * Decimal(TOP_TIER_INCENTIVE_NUM)) / Decimal(TOP_TIER_INCENTIVE_DEN)
        sale_top_tier_incentive_minor = _clamp_minor(int(raw.quantize(Decimal("1"), rounding=ROUND_HALF_UP)))
        sale_platform_minor = sale_fee_minor - sale_top_tier_incentive_minor
        if sale_platform_minor < 0:
            sale_platform_minor = 0

    delivery_actor_minor, delivery_platform_minor = _split_minor(
        delivery_minor,
        DELIVERY_ACTOR_BPS,
        DELIVERY_PLATFORM_BPS,
    )
    inspection_actor_minor, inspection_platform_minor = _split_minor(
        inspection_minor,
        INSPECTION_ACTOR_BPS,
        INSPECTION_PLATFORM_BPS,
    )

    return {
        "snapshot_version": SNAPSHOT_VERSION,
        "sale_kind": kind,
        "rules": {
            "sale": sale_rule,
            "delivery_split": DELIVERY_SPLIT_RULE_V1,
            "inspection_split": INSPECTION_SPLIT_RULE_V1,
            "top_tier_incentive": TOP_TIER_INCENTIVE_RULE_V1 if is_top_tier_flag else "NONE",
        },
        "inputs": {
            "sale_charge_minor": int(sale_charge_minor),
            "delivery_minor": int(delivery_minor),
            "inspection_minor": int(inspection_minor),
            "is_top_tier": bool(is_top_tier_flag),
            "sale_fee_bps": int(sale_bps),
        },
        "sale": {
            "charge_minor": int(sale_charge_minor),
            "fee_minor": int(sale_fee_minor),
            "seller_minor": int(sale_seller_minor),
            "platform_minor": int(sale_platform_minor),
            "top_tier_incentive_minor": int(sale_top_tier_incentive_minor),
        },
        "delivery": {
            "total_minor": int(delivery_minor),
            "actor_minor": int(delivery_actor_minor),
            "platform_minor": int(delivery_platform_minor),
        },
        "inspection": {
            "total_minor": int(inspection_minor),
            "actor_minor": int(inspection_actor_minor),
            "platform_minor": int(inspection_platform_minor),
        },
    }


def snapshot_to_order_columns(snapshot: dict | None) -> dict:
    data = snapshot if isinstance(snapshot, dict) else {}
    sale = data.get("sale") if isinstance(data.get("sale"), dict) else {}
    delivery = data.get("delivery") if isinstance(data.get("delivery"), dict) else {}
    inspection = data.get("inspection") if isinstance(data.get("inspection"), dict) else {}
    return {
        "commission_snapshot_version": int(data.get("snapshot_version") or SNAPSHOT_VERSION),
        "sale_fee_minor": int(sale.get("fee_minor") or 0),
        "sale_platform_minor": int(sale.get("platform_minor") or 0),
        "sale_seller_minor": int(sale.get("seller_minor") or 0),
        "sale_top_tier_incentive_minor": int(sale.get("top_tier_incentive_minor") or 0),
        "delivery_actor_minor": int(delivery.get("actor_minor") or 0),
        "delivery_platform_minor": int(delivery.get("platform_minor") or 0),
        "inspection_actor_minor": int(inspection.get("actor_minor") or 0),
        "inspection_platform_minor": int(inspection.get("platform_minor") or 0),
    }


def compute_commission(amount: float, rate: float) -> float:
    try:
        a = float(amount or 0.0)
        r = float(rate or 0.0)
        if a < 0:
            a = 0.0
        if r < 0:
            r = 0.0
        return round(a * r, 2)
    except Exception:
        return 0.0


# Default platform commission rates (can be moved to ENV later)
RATES = {
    "listing_sale": 0.05,
    "delivery": 0.10,
    "inspection": 0.10,
    "withdrawal": 0.0,
    "shortlet_booking": 0.05,
}


def resolve_rate(kind: str, state: str = "", category: str = "") -> float:
    """Resolve commission rate: DB rule (most specific) -> default RATES."""
    if (kind or "").strip() == "withdrawal":
        return 0.0
    try:
        from app.models import CommissionRule  # lazy import

        k = (kind or "").strip()
        s = (state or "").strip()
        c = (category or "").strip()

        q = CommissionRule.query.filter_by(kind=k, is_active=True)

        if s and c:
            r = q.filter(CommissionRule.state.ilike(s), CommissionRule.category.ilike(c)).first()
            if r:
                return float(r.rate or 0.0)

        if s:
            r = q.filter(CommissionRule.state.ilike(s), (CommissionRule.category.is_(None) | (CommissionRule.category == ""))).first()
            if r:
                return float(r.rate or 0.0)

        if c:
            r = q.filter(CommissionRule.category.ilike(c), (CommissionRule.state.is_(None) | (CommissionRule.state == ""))).first()
            if r:
                return float(r.rate or 0.0)

        r = q.filter((CommissionRule.state.is_(None) | (CommissionRule.state == "")), (CommissionRule.category.is_(None) | (CommissionRule.category == ""))).first()
        if r:
            return float(r.rate or 0.0)
    except Exception:
        pass

    return float(RATES.get((kind or "").strip(), 0.0))
