from datetime import datetime
import json

from app.extensions import db


class PlatformEvent(db.Model):
    __tablename__ = "platform_events"

    id = db.Column(db.Integer, primary_key=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)

    event_type = db.Column(db.String(80), nullable=False, index=True)
    actor_user_id = db.Column(db.Integer, nullable=True, index=True)

    subject_type = db.Column(db.String(80), nullable=True, index=True)
    subject_id = db.Column(db.String(120), nullable=True, index=True)

    request_id = db.Column(db.String(80), nullable=True, index=True)
    idempotency_key = db.Column(db.String(180), nullable=True, unique=True, index=True)

    severity = db.Column(db.String(16), nullable=False, default="INFO", index=True)
    metadata_json = db.Column(db.Text, nullable=True)

    def metadata_dict(self) -> dict:
        raw = self.metadata_json
        if not raw:
            return {}
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            pass
        return {"raw": str(raw)}

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "event_type": self.event_type or "",
            "actor_user_id": int(self.actor_user_id) if self.actor_user_id is not None else None,
            "subject_type": self.subject_type or "",
            "subject_id": self.subject_id or "",
            "request_id": self.request_id or "",
            "idempotency_key": self.idempotency_key or "",
            "severity": self.severity or "INFO",
            "metadata": self.metadata_dict(),
        }
