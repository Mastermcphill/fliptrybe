from datetime import datetime

from app.extensions import db


class PaymentIntentTransition(db.Model):
    __tablename__ = "payment_intent_transitions"
    __table_args__ = (
        db.UniqueConstraint("intent_id", "idempotency_key", name="uq_pi_transition_intent_key"),
    )

    id = db.Column(db.Integer, primary_key=True)
    intent_id = db.Column(db.Integer, nullable=False, index=True)
    from_status = db.Column(db.String(32), nullable=False, default="")
    to_status = db.Column(db.String(32), nullable=False)
    actor_type = db.Column(db.String(32), nullable=False, default="system")
    actor_id = db.Column(db.Integer, nullable=True)
    idempotency_key = db.Column(db.String(160), nullable=False)
    reason = db.Column(db.String(240), nullable=True)
    metadata_json = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": int(self.id),
            "intent_id": int(self.intent_id),
            "from_status": self.from_status or "",
            "to_status": self.to_status or "",
            "actor_type": self.actor_type or "",
            "actor_id": int(self.actor_id) if self.actor_id is not None else None,
            "idempotency_key": self.idempotency_key or "",
            "reason": self.reason or "",
            "metadata_json": self.metadata_json or "",
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
