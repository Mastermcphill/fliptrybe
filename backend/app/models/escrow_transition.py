from datetime import datetime

from app.extensions import db


class EscrowTransition(db.Model):
    __tablename__ = "escrow_transitions"
    __table_args__ = (
        db.UniqueConstraint("order_id", "idempotency_key", name="uq_escrow_transition_order_key"),
    )

    id = db.Column(db.Integer, primary_key=True)
    escrow_id = db.Column(db.String(64), nullable=False, index=True)
    order_id = db.Column(db.Integer, nullable=False, index=True)
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
            "escrow_id": self.escrow_id or "",
            "order_id": int(self.order_id),
            "from_status": self.from_status or "",
            "to_status": self.to_status or "",
            "actor_type": self.actor_type or "",
            "actor_id": int(self.actor_id) if self.actor_id is not None else None,
            "idempotency_key": self.idempotency_key or "",
            "reason": self.reason or "",
            "metadata_json": self.metadata_json or "",
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
