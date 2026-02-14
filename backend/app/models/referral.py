from datetime import datetime

from app.extensions import db


class Referral(db.Model):
    __tablename__ = "referrals"

    id = db.Column(db.Integer, primary_key=True)
    referrer_user_id = db.Column(
        db.Integer, db.ForeignKey("users.id"), nullable=False, index=True
    )
    referred_user_id = db.Column(
        db.Integer, db.ForeignKey("users.id"), nullable=False, index=True
    )
    referral_code = db.Column(db.String(32), nullable=False, index=True)
    status = db.Column(db.String(24), nullable=False, default="pending", index=True)
    reward_amount_minor = db.Column(db.Integer, nullable=False, default=0)
    reward_reference = db.Column(db.String(80), nullable=True, unique=True, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)
    completed_at = db.Column(db.DateTime, nullable=True)

    __table_args__ = (
        db.UniqueConstraint("referred_user_id", name="uq_referrals_referred_user"),
    )

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "referrer_user_id": int(self.referrer_user_id),
            "referred_user_id": int(self.referred_user_id),
            "referral_code": self.referral_code or "",
            "status": (self.status or "pending"),
            "reward_amount_minor": int(self.reward_amount_minor or 0),
            "reward_reference": self.reward_reference or "",
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
        }
