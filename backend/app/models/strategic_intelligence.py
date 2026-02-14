from __future__ import annotations

import json
from datetime import datetime

from app.extensions import db


def _json_dump(payload: dict | list | None) -> str:
    try:
        return json.dumps(payload or {}, separators=(",", ":"), ensure_ascii=False)
    except Exception:
        return "{}"


def _json_load(payload: str | None) -> dict:
    raw = (payload or "").strip()
    if not raw:
        return {}
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass
    return {}


class ElasticitySnapshot(db.Model):
    __tablename__ = "elasticity_snapshots"

    id = db.Column(db.Integer, primary_key=True)
    category = db.Column(db.String(24), nullable=False, index=True)
    city = db.Column(db.String(64), nullable=False, default="all", server_default="all", index=True)
    seller_type = db.Column(db.String(24), nullable=False, default="all", server_default="all", index=True)
    window_days = db.Column(db.Integer, nullable=False, default=90, server_default="90")
    sample_size = db.Column(db.Integer, nullable=False, default=0, server_default="0")
    elasticity_coefficient = db.Column(db.Float, nullable=False, default=0.0, server_default="0")
    confidence = db.Column(db.String(16), nullable=False, default="low", server_default="low")
    recommendation_shift_pct = db.Column(db.Float, nullable=False, default=0.0, server_default="0")
    metrics_json = db.Column(db.Text, nullable=False, default="{}", server_default="{}")
    hash_key = db.Column(db.String(96), nullable=False, unique=True, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)

    def metrics(self) -> dict:
        return _json_load(self.metrics_json)

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "category": self.category or "",
            "city": self.city or "all",
            "seller_type": self.seller_type or "all",
            "window_days": int(self.window_days or 0),
            "sample_size": int(self.sample_size or 0),
            "elasticity_coefficient": float(self.elasticity_coefficient or 0.0),
            "confidence": self.confidence or "low",
            "recommended_price_shift_pct": float(self.recommendation_shift_pct or 0.0),
            "metrics": self.metrics(),
            "hash_key": self.hash_key or "",
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class FraudFlag(db.Model):
    __tablename__ = "fraud_flags"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    score = db.Column(db.Integer, nullable=False, default=0, server_default="0", index=True)
    reasons_json = db.Column(db.Text, nullable=False, default="{}", server_default="{}")
    status = db.Column(db.String(24), nullable=False, default="open", server_default="open", index=True)
    reviewed_by_admin_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)
    reviewed_at = db.Column(db.DateTime, nullable=True)
    action_note = db.Column(db.String(240), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)

    def reasons(self) -> dict:
        return _json_load(self.reasons_json)

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "user_id": int(self.user_id or 0),
            "score": int(self.score or 0),
            "reasons": self.reasons(),
            "status": self.status or "open",
            "reviewed_by_admin_id": int(self.reviewed_by_admin_id) if self.reviewed_by_admin_id is not None else None,
            "reviewed_at": self.reviewed_at.isoformat() if self.reviewed_at else None,
            "action_note": self.action_note or "",
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


def strategic_json_dump(payload: dict | list | None) -> str:
    return _json_dump(payload)
