from datetime import datetime

from app.extensions import db


class PaymentIntent(db.Model):
    __tablename__ = "payment_intents"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, nullable=False)

    provider = db.Column(db.String(32), nullable=False, default="paystack")
    reference = db.Column(db.String(128), nullable=False, unique=True)
    purpose = db.Column(db.String(32), nullable=False, default="topup")  # topup | order
    amount = db.Column(db.Float, nullable=False, default=0.0)

    status = db.Column(db.String(32), nullable=False, default="initialized")  # initialized|paid|failed

    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    paid_at = db.Column(db.DateTime, nullable=True)

    meta = db.Column(db.Text, nullable=True)

    def to_dict(self):
        return {
            "id": int(self.id),
            "user_id": int(self.user_id),
            "provider": self.provider,
            "reference": self.reference,
            "purpose": self.purpose,
            "amount": float(self.amount or 0.0),
            "status": self.status,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "paid_at": self.paid_at.isoformat() if self.paid_at else None,
            "meta": self.meta or "",
        }
