from datetime import datetime

from app.extensions import db


class Notification(db.Model):
    __tablename__ = "notifications"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)

    channel = db.Column(db.String(32), nullable=False, default="in_app")  # in_app | sms | whatsapp | email
    title = db.Column(db.String(160), nullable=True)
    message = db.Column(db.Text, nullable=False)

    status = db.Column(db.String(24), nullable=False, default="queued")  # queued | sent | failed
    provider = db.Column(db.String(64), nullable=True)  # twilio/termii/whatsapp_cloud etc
    provider_ref = db.Column(db.String(120), nullable=True)

    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    sent_at = db.Column(db.DateTime, nullable=True)

    meta = db.Column(db.Text, nullable=True)  # JSON string

    def _load_meta(self):
        raw = (self.meta or "").strip()
        if not raw:
            return {}
        try:
            import json

            data = json.loads(raw)
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    def _save_meta(self, meta: dict) -> None:
        try:
            import json

            self.meta = json.dumps(meta, separators=(",", ":"))
        except Exception:
            self.meta = "{}"

    def meta_dict(self):
        return self._load_meta()

    def mark_read(self, read_at: datetime | None = None) -> datetime:
        stamped = read_at or datetime.utcnow()
        meta = self._load_meta()
        meta["is_read"] = True
        meta["read_at"] = stamped.isoformat()
        self._save_meta(meta)
        return stamped

    def to_dict(self):
        meta = self.meta_dict()
        is_read = bool(meta.get("is_read"))
        read_at = meta.get("read_at")
        if isinstance(read_at, str):
            read_at = read_at.strip() or None
        else:
            read_at = None
        return {
            "id": self.id,
            "user_id": self.user_id,
            "channel": self.channel or "in_app",
            "title": self.title or "",
            "message": self.message or "",
            "status": self.status or "queued",
            "provider": self.provider or "",
            "provider_ref": self.provider_ref or "",
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "sent_at": self.sent_at.isoformat() if self.sent_at else None,
            "is_read": is_read,
            "read_at": read_at,
            "meta": meta,
        }
