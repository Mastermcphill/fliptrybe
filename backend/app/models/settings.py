from datetime import datetime

from app.extensions import db


class UserSettings(db.Model):
    __tablename__ = "user_settings"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, unique=True, index=True)

    notif_in_app = db.Column(db.Boolean, nullable=False, default=True)
    notif_sms = db.Column(db.Boolean, nullable=False, default=False)
    notif_whatsapp = db.Column(db.Boolean, nullable=False, default=False)

    dark_mode = db.Column(db.Boolean, nullable=False, default=False)
    preferred_city = db.Column(db.String(80), nullable=True)
    preferred_state = db.Column(db.String(80), nullable=True)

    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    def to_dict(self):
        return {
            "notif_in_app": bool(self.notif_in_app),
            "notif_sms": bool(self.notif_sms),
            "notif_whatsapp": bool(self.notif_whatsapp),
            "dark_mode": bool(self.dark_mode),
            "preferred_city": (self.preferred_city or ""),
            "preferred_state": (self.preferred_state or ""),
        }
