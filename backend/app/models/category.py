from datetime import datetime

import sqlalchemy as sa

from app.extensions import db


class Category(db.Model):
    __tablename__ = "categories"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    slug = db.Column(db.String(140), nullable=False, unique=True, index=True)
    parent_id = db.Column(db.Integer, db.ForeignKey("categories.id"), nullable=True, index=True)
    sort_order = db.Column(db.Integer, nullable=False, default=0, server_default="0")
    is_active = db.Column(db.Boolean, nullable=False, default=True, server_default=sa.text("true"))
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "name": self.name or "",
            "slug": self.slug or "",
            "parent_id": int(self.parent_id) if self.parent_id is not None else None,
            "sort_order": int(self.sort_order or 0),
            "is_active": bool(self.is_active),
        }
