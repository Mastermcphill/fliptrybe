from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP

from sqlalchemy import and_, or_

from app.extensions import db
from app.models import CommissionPolicy, CommissionPolicyRule


DEFAULT_DECLUTTER_BPS = 500
DEFAULT_SHORTLET_BPS = 500
DEFAULT_ALL_BPS = 500


@dataclass(frozen=True)
class CommissionResolution:
    policy_id: int | None
    policy_name: str
    rule_id: int | None
    applies_to: str
    seller_type: str
    city: str
    base_rate_bps: int
    promo_discount_bps: int
    effective_rate_bps: int
    min_fee_minor: int | None
    max_fee_minor: int | None
    source: str

    def to_dict(self) -> dict:
        return {
            "policy_id": self.policy_id,
            "policy_name": self.policy_name,
            "rule_id": self.rule_id,
            "applies_to": self.applies_to,
            "seller_type": self.seller_type,
            "city": self.city,
            "base_rate_bps": int(self.base_rate_bps),
            "promo_discount_bps": int(self.promo_discount_bps),
            "effective_rate_bps": int(self.effective_rate_bps),
            "min_fee_minor": int(self.min_fee_minor) if self.min_fee_minor is not None else None,
            "max_fee_minor": int(self.max_fee_minor) if self.max_fee_minor is not None else None,
            "source": self.source,
        }


def _normalize_applies_to(value: str | None) -> str:
    v = (value or "all").strip().lower()
    return v if v in ("all", "declutter", "shortlet") else "all"


def _normalize_seller_type(value: str | None) -> str:
    v = (value or "all").strip().lower()
    return v if v in ("all", "user", "merchant") else "all"


def _default_bps(applies_to: str) -> int:
    if applies_to == "shortlet":
        return DEFAULT_SHORTLET_BPS
    if applies_to == "declutter":
        return DEFAULT_DECLUTTER_BPS
    return DEFAULT_ALL_BPS


def _bps_minor_half_up(amount_minor: int, bps: int) -> int:
    amt = Decimal(max(0, int(amount_minor or 0)))
    rate = Decimal(max(0, int(bps or 0)))
    raw = (amt * rate) / Decimal("10000")
    return int(raw.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _rule_specificity(rule: CommissionPolicyRule, *, applies_to: str, seller_type: str, city: str) -> int:
    score = 0
    r_applies = _normalize_applies_to(rule.applies_to)
    r_seller = _normalize_seller_type(rule.seller_type)
    r_city = (rule.city or "").strip().lower()
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
    if rule.starts_at or rule.ends_at:
        score += 8
    return score


def get_active_policy(now: datetime | None = None) -> CommissionPolicy | None:
    _ = now  # reserved for future policy activation windows.
    return (
        CommissionPolicy.query.filter_by(status="active")
        .order_by(CommissionPolicy.activated_at.desc(), CommissionPolicy.id.desc())
        .first()
    )


def resolve_commission_policy(
    *,
    applies_to: str,
    seller_type: str = "all",
    city: str = "",
    at_time: datetime | None = None,
) -> CommissionResolution:
    now = at_time or datetime.utcnow()
    scope = _normalize_applies_to(applies_to)
    actor = _normalize_seller_type(seller_type)
    city_norm = (city or "").strip()

    policy = get_active_policy(now=now)
    if not policy:
        bps = _default_bps(scope)
        return CommissionResolution(
            policy_id=None,
            policy_name="default",
            rule_id=None,
            applies_to=scope,
            seller_type=actor,
            city=city_norm,
            base_rate_bps=bps,
            promo_discount_bps=0,
            effective_rate_bps=bps,
            min_fee_minor=None,
            max_fee_minor=None,
            source="default",
        )

    rules = (
        CommissionPolicyRule.query.filter_by(policy_id=int(policy.id))
        .filter(
            and_(
                or_(
                    CommissionPolicyRule.applies_to == "all",
                    CommissionPolicyRule.applies_to == scope,
                ),
                or_(
                    CommissionPolicyRule.seller_type == "all",
                    CommissionPolicyRule.seller_type == actor,
                ),
                or_(
                    CommissionPolicyRule.city.is_(None),
                    CommissionPolicyRule.city == "",
                    CommissionPolicyRule.city.ilike(city_norm),
                ),
                or_(CommissionPolicyRule.starts_at.is_(None), CommissionPolicyRule.starts_at <= now),
                or_(CommissionPolicyRule.ends_at.is_(None), CommissionPolicyRule.ends_at >= now),
            )
        )
        .all()
    )

    if not rules:
        bps = _default_bps(scope)
        return CommissionResolution(
            policy_id=int(policy.id),
            policy_name=policy.name or f"policy-{policy.id}",
            rule_id=None,
            applies_to=scope,
            seller_type=actor,
            city=city_norm,
            base_rate_bps=bps,
            promo_discount_bps=0,
            effective_rate_bps=bps,
            min_fee_minor=None,
            max_fee_minor=None,
            source="policy_fallback",
        )

    best = sorted(
        rules,
        key=lambda row: (
            _rule_specificity(row, applies_to=scope, seller_type=actor, city=city_norm),
            int(row.id or 0),
        ),
        reverse=True,
    )[0]

    base_rate = max(0, int(best.base_rate_bps or _default_bps(scope)))
    promo_discount = max(0, int(best.promo_discount_bps or 0))
    effective = max(0, base_rate - promo_discount)
    min_fee = int(best.min_fee_minor) if best.min_fee_minor is not None else None
    max_fee = int(best.max_fee_minor) if best.max_fee_minor is not None else None
    return CommissionResolution(
        policy_id=int(policy.id),
        policy_name=policy.name or f"policy-{policy.id}",
        rule_id=int(best.id),
        applies_to=scope,
        seller_type=actor,
        city=city_norm,
        base_rate_bps=base_rate,
        promo_discount_bps=promo_discount,
        effective_rate_bps=effective,
        min_fee_minor=min_fee,
        max_fee_minor=max_fee,
        source="policy_rule",
    )


def compute_fee_minor(
    *,
    amount_minor: int,
    applies_to: str,
    seller_type: str = "all",
    city: str = "",
    at_time: datetime | None = None,
) -> dict:
    resolution = resolve_commission_policy(
        applies_to=applies_to,
        seller_type=seller_type,
        city=city,
        at_time=at_time,
    )
    fee = _bps_minor_half_up(amount_minor, resolution.effective_rate_bps)
    if resolution.min_fee_minor is not None:
        fee = max(fee, int(resolution.min_fee_minor))
    if resolution.max_fee_minor is not None:
        fee = min(fee, int(resolution.max_fee_minor))
    return {
        "fee_minor": int(max(0, fee)),
        "policy": resolution.to_dict(),
    }


def create_policy(*, name: str, created_by_admin_id: int | None, notes: str = "") -> CommissionPolicy:
    row = CommissionPolicy(
        name=(name or "").strip() or "Untitled policy",
        status="draft",
        created_by_admin_id=created_by_admin_id,
        notes=(notes or "").strip() or None,
    )
    db.session.add(row)
    db.session.commit()
    return row


def add_policy_rule(
    *,
    policy_id: int,
    applies_to: str,
    seller_type: str,
    city: str = "",
    base_rate_bps: int = 500,
    min_fee_minor: int | None = None,
    max_fee_minor: int | None = None,
    promo_discount_bps: int | None = None,
    starts_at: datetime | None = None,
    ends_at: datetime | None = None,
) -> CommissionPolicyRule:
    rule = CommissionPolicyRule(
        policy_id=int(policy_id),
        applies_to=_normalize_applies_to(applies_to),
        seller_type=_normalize_seller_type(seller_type),
        city=(city or "").strip() or None,
        base_rate_bps=max(0, int(base_rate_bps or 0)),
        min_fee_minor=int(min_fee_minor) if min_fee_minor is not None else None,
        max_fee_minor=int(max_fee_minor) if max_fee_minor is not None else None,
        promo_discount_bps=int(promo_discount_bps) if promo_discount_bps is not None else None,
        starts_at=starts_at,
        ends_at=ends_at,
    )
    db.session.add(rule)
    db.session.commit()
    return rule


def activate_policy(policy_id: int) -> CommissionPolicy | None:
    target = db.session.get(CommissionPolicy, int(policy_id))
    if not target:
        return None
    now = datetime.utcnow()
    CommissionPolicy.query.filter(
        CommissionPolicy.id != int(target.id),
        CommissionPolicy.status == "active",
    ).update({"status": "archived"})
    target.status = "active"
    target.activated_at = now
    db.session.add(target)
    db.session.commit()
    return target


def archive_policy(policy_id: int) -> CommissionPolicy | None:
    target = db.session.get(CommissionPolicy, int(policy_id))
    if not target:
        return None
    target.status = "archived"
    db.session.add(target)
    db.session.commit()
    return target
