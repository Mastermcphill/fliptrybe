from __future__ import annotations

import json
from datetime import datetime

import sqlalchemy as sa

from app.extensions import db


class SavedSearch(db.Model):
    __tablename__ = "saved_searches"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    vertical = db.Column(db.String(32), nullable=False, default="marketplace", server_default="marketplace", index=True)
    name = db.Column(db.String(120), nullable=False)
    query_json = db.Column(db.Text, nullable=False, default="{}", server_default="{}")
    created_at = db.Column(db.DateTime(timezone=True), nullable=False, default=datetime.utcnow, server_default=sa.func.now())
    updated_at = db.Column(db.DateTime(timezone=True), nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow, server_default=sa.func.now())
    last_used_at = db.Column(db.DateTime(timezone=True), nullable=True)

    def _query_map(self) -> dict:
        raw = str(self.query_json or "").strip()
        if not raw:
            return {}
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            return {}
        return {}

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "user_id": int(self.user_id),
            "vertical": (self.vertical or "marketplace"),
            "name": (self.name or ""),
            "query_json": self._query_map(),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "last_used_at": self.last_used_at.isoformat() if self.last_used_at else None,
        }

