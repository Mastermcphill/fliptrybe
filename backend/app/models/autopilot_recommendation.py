from __future__ import annotations

import json
from datetime import datetime

from app.extensions import db


def _json_dumps(payload: dict | list | None) -> str:
    try:
        return json.dumps(payload or {}, separators=(",", ":"), ensure_ascii=False)
    except Exception:
        return "{}"


def _json_loads(payload: str | None) -> dict:
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


class AutopilotSnapshot(db.Model):
    __tablename__ = "autopilot_snapshots"

    id = db.Column(db.Integer, primary_key=True)
    window_days = db.Column(db.Integer, nullable=False, default=30, server_default="30", index=True)
    generated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)
    metrics_json = db.Column(db.Text, nullable=False, default="{}", server_default="{}")
    created_by_admin_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)
    hash_key = db.Column(db.String(96), nullable=False, unique=True, index=True)
    draft_policy_id = db.Column(db.Integer, db.ForeignKey("commission_policies.id"), nullable=True, index=True)

    def metrics(self) -> dict:
        return _json_loads(self.metrics_json)

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "window_days": int(self.window_days or 0),
            "generated_at": self.generated_at.isoformat() if self.generated_at else None,
            "created_by_admin_id": int(self.created_by_admin_id) if self.created_by_admin_id is not None else None,
            "hash_key": (self.hash_key or ""),
            "draft_policy_id": int(self.draft_policy_id) if self.draft_policy_id is not None else None,
            "metrics": self.metrics(),
        }


class AutopilotRecommendation(db.Model):
    __tablename__ = "autopilot_recommendations"

    id = db.Column(db.Integer, primary_key=True)
    snapshot_id = db.Column(db.Integer, db.ForeignKey("autopilot_snapshots.id"), nullable=False, index=True)
    applies_to = db.Column(db.String(24), nullable=False, default="declutter", server_default="declutter", index=True)
    seller_type = db.Column(db.String(24), nullable=False, default="all", server_default="all", index=True)
    city = db.Column(db.String(64), nullable=True, index=True)
    recommendation_json = db.Column(db.Text, nullable=False, default="{}", server_default="{}")
    status = db.Column(db.String(24), nullable=False, default="new", server_default="new", index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)

    def recommendation(self) -> dict:
        return _json_loads(self.recommendation_json)

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "snapshot_id": int(self.snapshot_id or 0),
            "applies_to": self.applies_to or "declutter",
            "seller_type": self.seller_type or "all",
            "city": self.city or "",
            "status": self.status or "new",
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "recommendation": self.recommendation(),
        }


class AutopilotEvent(db.Model):
    __tablename__ = "autopilot_events"

    id = db.Column(db.Integer, primary_key=True)
    event_type = db.Column(db.String(40), nullable=False, index=True)
    admin_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)
    payload_json = db.Column(db.Text, nullable=False, default="{}", server_default="{}")
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)

    def payload(self) -> dict:
        return _json_loads(self.payload_json)

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "event_type": self.event_type or "",
            "admin_id": int(self.admin_id) if self.admin_id is not None else None,
            "payload": self.payload(),
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


def recommendation_json_dumps(payload: dict | list | None) -> str:
    return _json_dumps(payload)
