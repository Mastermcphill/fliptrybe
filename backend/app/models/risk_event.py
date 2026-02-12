from datetime import datetime

from app.extensions import db


class RiskEvent(db.Model):
    __tablename__ = "risk_events"

    id = db.Column(db.Integer, primary_key=True)
    action = db.Column(db.String(80), nullable=False, index=True)
    score = db.Column(db.Float, nullable=False, default=0.0)
    flags_json = db.Column(db.Text, nullable=True)
    decision = db.Column(db.String(64), nullable=False, default="allow")
    reason_code = db.Column(db.String(120), nullable=True, index=True)
    user_id = db.Column(db.Integer, nullable=True, index=True)
    request_id = db.Column(db.String(64), nullable=True, index=True)
    context_json = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)

    def to_dict(self):
        return {
            "id": int(self.id),
            "action": self.action or "",
            "score": float(self.score or 0.0),
            "flags_json": self.flags_json or "",
            "decision": self.decision or "",
            "reason_code": self.reason_code or "",
            "user_id": int(self.user_id) if self.user_id is not None else None,
            "request_id": self.request_id or "",
            "context_json": self.context_json or "",
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
