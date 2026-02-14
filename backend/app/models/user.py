from datetime import datetime
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash

from app.extensions import db


class User(db.Model, UserMixin):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)

    name = db.Column(db.String(120), nullable=False, default="")
    email = db.Column(db.String(255), unique=True, index=True, nullable=False)

    phone = db.Column(db.String(32), unique=True, index=True, nullable=True)
    profile_image_url = db.Column(db.String(1024), nullable=True)

    password_hash = db.Column(db.String(255), nullable=False)

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    is_verified = db.Column(db.Boolean, nullable=False, default=False)

    role = db.Column(db.String(32), nullable=False, default='buyer')
    referral_code = db.Column(db.String(32), nullable=True, unique=True, index=True)
    referred_by = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)

    # KYC tier: 0=unverified, 1=basic, 2=verified
    kyc_tier = db.Column(db.Integer, nullable=False, default=0)

    # Driver availability (for driver role)
    is_available = db.Column(db.Boolean, nullable=False, default=True)

    def set_password(self, raw_password: str) -> None:
        self.password_hash = generate_password_hash(raw_password)

    def check_password(self, raw_password: str) -> bool:
        return check_password_hash(self.password_hash, raw_password)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "email": self.email,
            "phone": getattr(self, "phone", None),
            "profile_image_url": (getattr(self, "profile_image_url", None) or ""),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "is_verified": bool(self.is_verified),
            "role": self.role or "buyer",
            "referral_code": (getattr(self, "referral_code", None) or ""),
            "referred_by": int(getattr(self, "referred_by", 0) or 0) or None,
            "kyc_tier": int(getattr(self, "kyc_tier", 0) or 0),
            "is_available": bool(getattr(self, "is_available", True)),
        }
