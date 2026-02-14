from __future__ import annotations

from datetime import datetime

from app.extensions import db


class PricingBenchmark(db.Model):
    __tablename__ = "pricing_benchmarks"

    id = db.Column(db.Integer, primary_key=True)
    category = db.Column(db.String(24), nullable=False, index=True)
    city = db.Column(db.String(64), nullable=False, index=True)
    item_type = db.Column(db.String(120), nullable=True, index=True)
    p25_minor = db.Column(db.Integer, nullable=False, default=0, server_default="0")
    p50_minor = db.Column(db.Integer, nullable=False, default=0, server_default="0")
    p75_minor = db.Column(db.Integer, nullable=False, default=0, server_default="0")
    sample_size = db.Column(db.Integer, nullable=False, default=0, server_default="0")
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)

    __table_args__ = (
        db.UniqueConstraint("category", "city", "item_type", name="uq_pricing_benchmark_scope"),
    )

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "category": self.category or "",
            "city": self.city or "",
            "item_type": self.item_type or "",
            "p25_minor": int(self.p25_minor or 0),
            "p50_minor": int(self.p50_minor or 0),
            "p75_minor": int(self.p75_minor or 0),
            "sample_size": int(self.sample_size or 0),
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


class CommissionPolicy(db.Model):
    __tablename__ = "commission_policies"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    status = db.Column(db.String(16), nullable=False, default="draft", index=True)
    created_by_admin_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)
    activated_at = db.Column(db.DateTime, nullable=True, index=True)
    notes = db.Column(db.Text, nullable=True)

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "name": self.name or "",
            "status": (self.status or "draft"),
            "created_by_admin_id": int(self.created_by_admin_id) if self.created_by_admin_id is not None else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "activated_at": self.activated_at.isoformat() if self.activated_at else None,
            "notes": self.notes or "",
        }


class CommissionPolicyRule(db.Model):
    __tablename__ = "commission_policy_rules"

    id = db.Column(db.Integer, primary_key=True)
    policy_id = db.Column(db.Integer, db.ForeignKey("commission_policies.id"), nullable=False, index=True)
    applies_to = db.Column(db.String(24), nullable=False, default="all", index=True)
    seller_type = db.Column(db.String(24), nullable=False, default="all", index=True)
    city = db.Column(db.String(64), nullable=True, index=True)
    base_rate_bps = db.Column(db.Integer, nullable=False, default=500, server_default="500")
    min_fee_minor = db.Column(db.Integer, nullable=True)
    max_fee_minor = db.Column(db.Integer, nullable=True)
    promo_discount_bps = db.Column(db.Integer, nullable=True)
    starts_at = db.Column(db.DateTime, nullable=True, index=True)
    ends_at = db.Column(db.DateTime, nullable=True, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "policy_id": int(self.policy_id),
            "applies_to": self.applies_to or "all",
            "seller_type": self.seller_type or "all",
            "city": self.city or "",
            "base_rate_bps": int(self.base_rate_bps or 0),
            "min_fee_minor": int(self.min_fee_minor or 0) if self.min_fee_minor is not None else None,
            "max_fee_minor": int(self.max_fee_minor or 0) if self.max_fee_minor is not None else None,
            "promo_discount_bps": int(self.promo_discount_bps or 0) if self.promo_discount_bps is not None else None,
            "starts_at": self.starts_at.isoformat() if self.starts_at else None,
            "ends_at": self.ends_at.isoformat() if self.ends_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
