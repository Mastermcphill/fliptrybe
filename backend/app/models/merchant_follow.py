from datetime import datetime

from app.extensions import db


class MerchantFollow(db.Model):
    __tablename__ = "merchant_follows"
    __table_args__ = (
        db.UniqueConstraint("follower_id", "merchant_id", name="uq_merchant_follows_follower_merchant"),
        {"extend_existing": True},
    )

    id = db.Column(db.Integer, primary_key=True)
    follower_id = db.Column(db.Integer, nullable=False, index=True)
    merchant_id = db.Column(db.Integer, nullable=False, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
