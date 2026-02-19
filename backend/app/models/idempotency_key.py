from datetime import datetime

from app.extensions import db


class IdempotencyKey(db.Model):
    __tablename__ = "idempotency_keys"
    __table_args__ = (
        db.UniqueConstraint("scope", "key", name="uq_idempotency_scope_key"),
    )

    id = db.Column(db.Integer, primary_key=True)

    key = db.Column(db.String(128), nullable=False, index=True)
    scope = db.Column(db.String(128), nullable=False, default="", server_default="")
    user_id = db.Column(db.Integer, nullable=True)
    route = db.Column(db.String(128), nullable=False, default="", server_default="")
    request_hash = db.Column(db.String(64), nullable=False, default="")

    response_json = db.Column(db.Text, nullable=True)
    status_code = db.Column(db.Integer, nullable=False, default=200, server_default="200")
    response_body_json = db.Column(db.Text, nullable=True)
    response_code = db.Column(db.Integer, nullable=False, default=200, server_default="200")

    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)

    @property
    def effective_scope(self) -> str:
        return (self.scope or self.route or "").strip()

    def to_dict(self):
        return {
            "id": int(self.id),
            "key": self.key,
            "scope": self.effective_scope,
            "user_id": int(self.user_id) if self.user_id is not None else None,
            "route": self.route,
            "request_hash": self.request_hash,
            "status_code": int(self.status_code),
            "response_code": int(self.response_code or self.status_code or 200),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
