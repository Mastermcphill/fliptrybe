from datetime import datetime

from app.extensions import db


class WebhookEvent(db.Model):
    __tablename__ = "webhook_events"

    id = db.Column(db.Integer, primary_key=True)
    provider = db.Column(db.String(32), nullable=False, default="paystack")
    event_id = db.Column(db.String(128), nullable=False, unique=True)
    reference = db.Column(db.String(128), nullable=True)
    status = db.Column(db.String(32), nullable=False, default="received")
    processed_at = db.Column(db.DateTime, nullable=True)
    request_id = db.Column(db.String(64), nullable=True)
    payload_hash = db.Column(db.String(128), nullable=True)
    payload_json = db.Column(db.Text, nullable=True)
    error = db.Column(db.Text, nullable=True)

    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": int(self.id),
            "provider": self.provider,
            "event_id": self.event_id,
            "reference": self.reference or "",
            "status": self.status or "",
            "processed_at": self.processed_at.isoformat() if self.processed_at else None,
            "request_id": self.request_id or "",
            "payload_hash": self.payload_hash or "",
            "error": self.error or "",
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
