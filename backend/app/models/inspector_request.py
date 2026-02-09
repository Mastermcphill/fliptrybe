from datetime import datetime

from app.extensions import db


class InspectorRequest(db.Model):
    __tablename__ = "inspector_requests"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(200), nullable=False)
    email = db.Column(db.String(200), nullable=False, index=True)
    phone = db.Column(db.String(50), nullable=False, index=True)
    notes = db.Column(db.Text)
    status = db.Column(db.String(40), nullable=False, default="pending", index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    decided_at = db.Column(db.DateTime)
    decided_by = db.Column(db.Integer)

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "name": (self.name or ""),
            "email": (self.email or ""),
            "phone": (self.phone or ""),
            "notes": (self.notes or ""),
            "status": (self.status or "pending"),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "decided_at": self.decided_at.isoformat() if self.decided_at else None,
            "decided_by": int(self.decided_by) if self.decided_by is not None else None,
        }
