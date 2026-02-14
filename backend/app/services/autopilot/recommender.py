from __future__ import annotations

import os
from datetime import datetime, timedelta


def _env_int(name: str, default: int) -> int:
    raw = (os.getenv(name) or "").strip()
    if not raw:
        return int(default)
    try:
        return int(raw)
    except Exception:
        return int(default)


def _env_float(name: str, default: float) -> float:
    raw = (os.getenv(name) or "").strip()
    if not raw:
        return float(default)
    try:
        return float(raw)
    except Exception:
        return float(default)


def autopilot_constants() -> dict:
    return {
        "max_bps_change": max(25, min(300, _env_int("AUTOPILOT_MAX_BPS_CHANGE", 150))),
        "min_sample_orders": max(5, _env_int("AUTOPILOT_MIN_SAMPLE_ORDERS", 30)),
        "target_conversion": max(0.01, _env_float("AUTOPILOT_TARGET_CONVERSION", 0.2)),
        "liquidity_risk_threshold": max(0.5, _env_float("AUTOPILOT_LIQUIDITY_RISK_THRESHOLD", 8.0)),
        "max_days_to_negative": max(15, _env_int("AUTOPILOT_MAX_DAYS_TO_NEGATIVE", 60)),
        "abuse_chargeback_threshold": max(0.01, _env_float("AUTOPILOT_ABUSE_CHARGEBACK_THRESHOLD", 0.03)),
        "abuse_dispute_threshold": max(3, _env_int("AUTOPILOT_ABUSE_DISPUTE_THRESHOLD", 5)),
        "demand_drop_pct": min(-5.0, _env_float("AUTOPILOT_DEMAND_DROP_PCT", -12.0)),
        "elasticity": max(0.0, min(1.0, _env_float("AUTOPILOT_ELASTICITY", 0.12))),
    }


def min_days_between_drafts() -> int:
    return max(1, _env_int("AUTOPILOT_MIN_DAYS_BETWEEN_DRAFTS", 7))


def _confidence(sample_size: int) -> str:
    if sample_size >= 120:
        return "high"
    if sample_size >= 45:
        return "medium"
    return "low"


def _bounded_delta(value: int, limit: int) -> int:
    if value > limit:
        return int(limit)
    if value < -limit:
        return int(-limit)
    return int(value)


def _estimate_impact(gmv_minor: int, delta_bps: int, elasticity: float) -> dict:
    base = int(round((int(gmv_minor) * int(delta_bps)) / 10000.0))
    gmv_shift = int(round(float(gmv_minor) * float(elasticity) * (-float(delta_bps) / 10000.0)))
    return {
        "revenue_delta_minor": int(base),
        "gmv_delta_minor": int(gmv_shift),
    }


def _recommendation_payload(*, segment: dict, reason_code: str, title: str, action: dict, explanation: list[str], risk_flags: list[str], expected_impact: dict) -> dict:
    return {
        "reason_code": reason_code,
        "title": title,
        "action": action,
        "applies_to": segment.get("applies_to"),
        "seller_type": segment.get("seller_type"),
        "city": segment.get("city"),
        "baseline": {
            "order_count": int(segment.get("order_count") or 0),
            "previous_order_count": int(segment.get("previous_order_count") or 0),
            "orders_delta_pct": float(segment.get("orders_delta_pct") or 0.0),
            "gmv_minor": int(segment.get("gmv_minor") or 0),
            "gmv_delta_pct": float(segment.get("gmv_delta_pct") or 0.0),
            "conversion_orders_per_active_listing": float(segment.get("conversion_orders_per_active_listing") or 0.0),
            "active_listings_count": int(segment.get("active_listings_count") or 0),
            "active_listings_delta_pct": float(segment.get("active_listings_delta_pct") or 0.0),
        },
        "expected_impact": expected_impact,
        "risk_flags": risk_flags,
        "confidence": _confidence(int(segment.get("order_count") or 0)),
        "explanation": explanation,
        "rule_payload": {
            "applies_to": segment.get("applies_to") or "declutter",
            "seller_type": segment.get("seller_type") or "all",
            "city": "" if (segment.get("city") or "all") == "all" else (segment.get("city") or ""),
            "base_rate_bps": int(action.get("base_rate_bps") or 500),
            "min_fee_minor": action.get("min_fee_minor"),
            "max_fee_minor": action.get("max_fee_minor"),
            "promo_discount_bps": action.get("promo_discount_bps"),
            "starts_at": action.get("starts_at"),
            "ends_at": action.get("ends_at"),
        },
    }


def generate_recommendations(metrics: dict) -> list[dict]:
    constants = autopilot_constants()
    segments = list(metrics.get("segments") or [])
    if not segments:
        return []

    liquidity = metrics.get("liquidity") or {}
    payout_pressure = float(liquidity.get("payout_pressure") or 0.0)
    float_min = int(liquidity.get("float_min_30d_minor") or 0)
    days_to_negative = liquidity.get("days_to_negative")
    liquidity_risk = bool(
        payout_pressure >= constants["liquidity_risk_threshold"]
        or (days_to_negative is not None and int(days_to_negative) <= constants["max_days_to_negative"])
        or float_min <= 0
    )

    segments_sorted = sorted(
        segments,
        key=lambda row: (int(row.get("gmv_minor") or 0), int(row.get("order_count") or 0)),
        reverse=True,
    )

    recommendations: list[dict] = []
    for segment in segments_sorted:
        sample_orders = int(segment.get("order_count") or 0)
        if sample_orders < constants["min_sample_orders"]:
            continue

        current_bps = int(((segment.get("current_policy") or {}).get("effective_rate_bps") or 500))
        gmv_minor = int(segment.get("gmv_minor") or 0)
        conversion = float(segment.get("conversion_orders_per_active_listing") or 0.0)
        active_count = int(segment.get("active_listings_count") or 0)
        orders_delta = float(segment.get("orders_delta_pct") or 0.0)
        active_delta = float(segment.get("active_listings_delta_pct") or 0.0)
        quality = segment.get("quality") or {}
        chargeback_rate = float(quality.get("chargeback_rate") or 0.0)
        dispute_count = int(quality.get("dispute_count") or 0)
        abuse_guard = chargeback_rate >= constants["abuse_chargeback_threshold"] or dispute_count >= constants["abuse_dispute_threshold"]

        if liquidity_risk:
            delta = _bounded_delta(max(25, int(round(current_bps * 0.1))), constants["max_bps_change"])
            new_bps = int(max(0, current_bps + delta))
            impact = _estimate_impact(gmv_minor, delta, constants["elasticity"])
            title = (
                f"Increase commission by {delta / 100:.2f}% for "
                f"{segment.get('applies_to')} / {segment.get('seller_type')} / {segment.get('city')}"
            )
            recommendations.append(
                _recommendation_payload(
                    segment=segment,
                    reason_code="LIQUIDITY_STRESS",
                    title=title,
                    action={"type": "adjust_base_rate_bps", "delta_bps": delta, "base_rate_bps": new_bps},
                    explanation=[
                        f"Payout pressure is {payout_pressure:.2f}x daily commission.",
                        f"Projected days to negative cash: {days_to_negative}.",
                        f"Applying +{delta} bps on current {current_bps} bps to stabilize platform float.",
                    ],
                    risk_flags=["LIQUIDITY_RISK_ELEVATED"],
                    expected_impact=impact,
                )
            )
            continue

        if conversion >= constants["target_conversion"] * 1.25 and active_count > 0:
            delta = _bounded_delta(-50, constants["max_bps_change"])
            if abuse_guard:
                delta = 0
            if delta != 0:
                new_bps = int(max(0, current_bps + delta))
                impact = _estimate_impact(gmv_minor, delta, constants["elasticity"])
                title = (
                    f"Reduce commission by {abs(delta) / 100:.2f}% to ease supply pressure for "
                    f"{segment.get('applies_to')} / {segment.get('city')}"
                )
                recommendations.append(
                    _recommendation_payload(
                        segment=segment,
                        reason_code="SUPPLY_SHORTAGE",
                        title=title,
                        action={"type": "adjust_base_rate_bps", "delta_bps": delta, "base_rate_bps": new_bps},
                        explanation=[
                            f"Conversion proxy is high at {conversion:.3f} orders per active listing.",
                            "Lower commission can attract new listings in constrained segments.",
                            f"Current rate {current_bps} bps, proposed {new_bps} bps.",
                        ],
                        risk_flags=["SUPPLY_CONSTRAINT"],
                        expected_impact=impact,
                    )
                )
            elif abuse_guard:
                recommendations.append(
                    _recommendation_payload(
                        segment=segment,
                        reason_code="ABUSE_GUARD_BLOCK",
                        title=f"Hold commission reduction for {segment.get('applies_to')} / {segment.get('city')}",
                        action={"type": "no_change", "base_rate_bps": current_bps},
                        explanation=[
                            "Supply signal suggested a reduction.",
                            f"Blocked because dispute/refund risk is elevated (chargeback_rate={chargeback_rate:.4f}, disputes={dispute_count}).",
                        ],
                        risk_flags=["QUALITY_RISK", "REDUCTION_BLOCKED"],
                        expected_impact={"revenue_delta_minor": 0, "gmv_delta_minor": 0},
                    )
                )

        if orders_delta <= constants["demand_drop_pct"] and abs(active_delta) <= 12.0:
            promo = min(100, constants["max_bps_change"])
            if abuse_guard:
                continue
            starts_at = datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
            ends_at = (datetime.utcnow() + timedelta(days=21)).replace(microsecond=0).isoformat() + "Z"
            impact = _estimate_impact(gmv_minor, -promo, constants["elasticity"])
            title = (
                f"Apply temporary {promo / 100:.2f}% promo discount for "
                f"{segment.get('applies_to')} / {segment.get('city')}"
            )
            recommendations.append(
                _recommendation_payload(
                    segment=segment,
                    reason_code="DEMAND_SLOWDOWN",
                    title=title,
                    action={
                        "type": "promo_discount",
                        "base_rate_bps": current_bps,
                        "promo_discount_bps": promo,
                        "starts_at": starts_at,
                        "ends_at": ends_at,
                    },
                    explanation=[
                        f"Orders are down {orders_delta:.2f}% while supply is comparatively stable ({active_delta:.2f}%).",
                        "Time-boxed discount can stimulate demand without permanent fee changes.",
                        f"Promo period: {starts_at} to {ends_at}.",
                    ],
                    risk_flags=["DEMAND_SOFTNESS"],
                    expected_impact=impact,
                )
            )

        if (segment.get("seller_type") or "") == "merchant" and orders_delta < -5.0:
            promo = min(80, constants["max_bps_change"])
            if abuse_guard:
                continue
            starts_at = datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
            ends_at = (datetime.utcnow() + timedelta(days=14)).replace(microsecond=0).isoformat() + "Z"
            impact = _estimate_impact(gmv_minor, -promo, constants["elasticity"])
            title = f"Merchant activation promo: {promo / 100:.2f}% discount for {segment.get('applies_to')} / {segment.get('city')}"
            recommendations.append(
                _recommendation_payload(
                    segment=segment,
                    reason_code="MERCHANT_ACTIVATION",
                    title=title,
                    action={
                        "type": "promo_discount",
                        "base_rate_bps": current_bps,
                        "promo_discount_bps": promo,
                        "starts_at": starts_at,
                        "ends_at": ends_at,
                    },
                    explanation=[
                        "Merchant segment activity slowed versus previous window.",
                        "Temporary discount is scoped to merchant sellers to recover listing momentum.",
                    ],
                    risk_flags=["TIME_BOXED_PROMO"],
                    expected_impact=impact,
                )
            )

    unique_titles: set[str] = set()
    deduped: list[dict] = []
    for row in recommendations:
        key = f"{row.get('reason_code')}|{row.get('applies_to')}|{row.get('seller_type')}|{row.get('city')}|{(row.get('action') or {}).get('type')}"
        if key in unique_titles:
            continue
        unique_titles.add(key)
        deduped.append(row)
    return deduped


def _rule_specificity(rule: dict, *, applies_to: str, seller_type: str, city: str) -> tuple[int, int]:
    score = 0
    r_applies = (rule.get("applies_to") or "all").strip().lower()
    r_seller = (rule.get("seller_type") or "all").strip().lower()
    r_city = (rule.get("city") or "").strip().lower()
    city_norm = (city or "").strip().lower()
    if r_applies == applies_to:
        score += 40
    elif r_applies == "all":
        score += 5
    if r_seller == seller_type:
        score += 25
    elif r_seller == "all":
        score += 5
    if r_city and city_norm and r_city == city_norm:
        score += 30
    elif not r_city:
        score += 3
    return (score, int(rule.get("id") or 0))


def preview_policy_impact(*, draft_policy: dict, rules: list[dict], signals: dict) -> dict:
    segments = list(signals.get("segments") or [])
    constants = autopilot_constants()
    total_revenue_delta = 0
    total_gmv_delta = 0
    baseline_fee_minor = 0
    proposed_fee_minor = 0
    weighted_bps_num = 0
    weighted_bps_den = 0
    risk_flags: list[str] = []
    breakdown: list[dict] = []

    for segment in segments:
        gmv_minor = int(segment.get("gmv_minor") or 0)
        if gmv_minor <= 0:
            continue
        applies_to = (segment.get("applies_to") or "declutter").strip().lower()
        seller_type = (segment.get("seller_type") or "all").strip().lower()
        city = "" if (segment.get("city") or "all") == "all" else (segment.get("city") or "")
        current_bps = int(((segment.get("current_policy") or {}).get("effective_rate_bps") or 500))

        matches = sorted(
            [
                rule
                for rule in rules
                if (rule.get("applies_to") in ("all", applies_to))
                and (rule.get("seller_type") in ("all", seller_type))
                and (((rule.get("city") or "").strip() == "") or ((rule.get("city") or "").strip().lower() == city.strip().lower()))
            ],
            key=lambda row: _rule_specificity(row, applies_to=applies_to, seller_type=seller_type, city=city),
            reverse=True,
        )
        matched = matches[0] if matches else None
        proposed_bps = current_bps
        if matched:
            base = int(matched.get("base_rate_bps") or current_bps)
            promo = int(matched.get("promo_discount_bps") or 0)
            proposed_bps = max(0, base - promo)

        baseline_fee = int(round((gmv_minor * current_bps) / 10000.0))
        proposed_fee = int(round((gmv_minor * proposed_bps) / 10000.0))
        revenue_delta = proposed_fee - baseline_fee
        gmv_delta = int(round(float(gmv_minor) * constants["elasticity"] * (-float(proposed_bps - current_bps) / 10000.0)))

        baseline_fee_minor += baseline_fee
        proposed_fee_minor += proposed_fee
        total_revenue_delta += revenue_delta
        total_gmv_delta += gmv_delta
        weighted_bps_num += proposed_bps * gmv_minor
        weighted_bps_den += gmv_minor
        breakdown.append(
            {
                "applies_to": applies_to,
                "seller_type": seller_type,
                "city": segment.get("city") or "all",
                "current_bps": current_bps,
                "proposed_bps": proposed_bps,
                "gmv_minor": gmv_minor,
                "revenue_delta_minor": revenue_delta,
                "gmv_delta_minor": gmv_delta,
            }
        )

    avg_proposed_bps = int(round(weighted_bps_num / weighted_bps_den)) if weighted_bps_den > 0 else 500
    if total_revenue_delta < 0:
        risk_flags.append("REVENUE_DOWN")
    if avg_proposed_bps < 350:
        risk_flags.append("LOW_EFFECTIVE_BPS")

    return {
        "ok": True,
        "draft_policy_id": draft_policy.get("id"),
        "draft_policy_name": draft_policy.get("name"),
        "baseline_fee_minor": int(baseline_fee_minor),
        "proposed_fee_minor": int(proposed_fee_minor),
        "projected_revenue_delta_minor": int(total_revenue_delta),
        "projected_gmv_delta_minor": int(total_gmv_delta),
        "weighted_proposed_bps": int(avg_proposed_bps),
        "risk_flags": risk_flags,
        "segments": breakdown,
    }
