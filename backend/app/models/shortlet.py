from datetime import datetime, date
import json
from app.extensions import db


def _safe_json_list(raw: str | None):
    if not raw:
        return []
    try:
        v = json.loads(raw)
        if isinstance(v, list):
            return v
        return []
    except Exception:
        return []


class Shortlet(db.Model):

    __tablename__ = "shortlets"

    id = db.Column(db.Integer, primary_key=True)

    owner_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)

    title = db.Column(db.String(160), nullable=False)
    description = db.Column(db.Text, nullable=True)

    # Location (Nigeria-first)
    state = db.Column(db.String(64), nullable=True)
    city = db.Column(db.String(64), nullable=True)
    locality = db.Column(db.String(96), nullable=True)
    lga = db.Column(db.String(96), nullable=True)

    latitude = db.Column(db.Float, nullable=True)
    longitude = db.Column(db.Float, nullable=True)

    # Shortlet-specific
    nightly_price = db.Column(db.Float, nullable=False, default=0.0)
    # Transparent pricing (merchant add-on)
    base_price = db.Column(db.Float, nullable=False, default=0.0)
    platform_fee = db.Column(db.Float, nullable=False, default=0.0)
    final_price = db.Column(db.Float, nullable=False, default=0.0)
    cleaning_fee = db.Column(db.Float, nullable=False, default=0.0)

    beds = db.Column(db.Integer, nullable=False, default=1)
    baths = db.Column(db.Integer, nullable=False, default=1)
    guests = db.Column(db.Integer, nullable=False, default=2)

    # Availability window (simple for MVP)
    available_from = db.Column(db.Date, nullable=True)
    available_to = db.Column(db.Date, nullable=True)

    image_path = db.Column(db.String(512), nullable=True)

    property_type = db.Column(db.String(64), nullable=True)  # studio, 1br, 2br, duplex, etc.
    amenities = db.Column(db.Text, nullable=True)  # JSON string list
    house_rules = db.Column(db.Text, nullable=True)  # JSON string list

    rating = db.Column(db.Float, nullable=False, default=0.0)
    reviews_count = db.Column(db.Integer, nullable=False, default=0)
    verification_score = db.Column(db.Integer, nullable=False, default=0)  # 0-100
    views_count = db.Column(db.Integer, nullable=False, default=0, server_default="0")
    favorites_count = db.Column(db.Integer, nullable=False, default=0, server_default="0")
    heat_level = db.Column(db.String(16), nullable=False, default="normal", server_default="normal")
    heat_score = db.Column(db.Integer, nullable=False, default=0, server_default="0")

    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)


    def _amenities_list(self):
        raw = (self.amenities or "").strip()
        if not raw:
            return []
        try:
            import json
            data = json.loads(raw)
            if isinstance(data, list):
                return [str(x) for x in data if str(x).strip() != ""]
        except Exception:
            pass
        # fallback: comma-separated
        return [x.strip() for x in raw.split(",") if x.strip() != ""]

    def to_dict(self, base_url: str | None = None):
        img = (self.image_path or "").strip()
        if base_url and img and not (img.lower().startswith("http://") or img.lower().startswith("https://")):
            if not img.startswith("/"):
                img = "/" + img
            img = f"{base_url.rstrip('/')}{img}"
        base_price = float(self.base_price or 0.0) if self.base_price is not None else 0.0
        platform_fee = float(self.platform_fee or 0.0) if self.platform_fee is not None else 0.0
        final_price = float(self.final_price or 0.0) if self.final_price is not None else 0.0
        if base_price <= 0.0:
            base_price = float(self.nightly_price or 0.0)
        if final_price <= 0.0:
            final_price = base_price + platform_fee

        return {
            "id": self.id,
            "owner_id": int(self.owner_id) if self.owner_id is not None else None,
            "title": self.title,
            "description": self.description or "",
            "state": self.state or "",
            "city": self.city or "",
            "locality": self.locality or "",
            "lga": self.lga or "",
            "latitude": float(self.latitude) if self.latitude is not None else None,
            "longitude": float(self.longitude) if self.longitude is not None else None,
            "nightly_price": float(final_price),
            "base_price": float(base_price),
            "platform_fee": float(platform_fee),
            "final_price": float(final_price),
            "cleaning_fee": float(self.cleaning_fee or 0.0),
            "beds": int(self.beds or 0),
            "baths": int(self.baths or 0),
            "guests": int(self.guests or 0),
            "available_from": self.available_from.isoformat() if self.available_from else None,
            "available_to": self.available_to.isoformat() if self.available_to else None,
            "image": img,
            "property_type": (self.property_type or ""),
            "amenities": _safe_json_list(self.amenities),
            "house_rules": _safe_json_list(self.house_rules),
            "rating": float(self.rating or 0.0),
            "reviews_count": int(self.reviews_count or 0),
            "verification_score": int(self.verification_score or 0),
            "views_count": int(getattr(self, "views_count", 0) or 0),
            "favorites_count": int(getattr(self, "favorites_count", 0) or 0),
            "heat_level": (getattr(self, "heat_level", "normal") or "normal"),
            "heat_score": int(getattr(self, "heat_score", 0) or 0),
            "image_path": img,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class ShortletBooking(db.Model):
    __tablename__ = "shortlet_bookings"

    id = db.Column(db.Integer, primary_key=True)
    shortlet_id = db.Column(db.Integer, db.ForeignKey("shortlets.id"), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)
    payment_intent_id = db.Column(db.Integer, db.ForeignKey("payment_intents.id"), nullable=True, index=True)
    payment_status = db.Column(db.String(32), nullable=False, default="pending")
    payment_method = db.Column(db.String(48), nullable=False, default="wallet")
    amount_minor = db.Column(db.Integer, nullable=False, default=0)

    # In future: user_id, payment refs, etc.
    guest_name = db.Column(db.String(120), nullable=True)
    guest_phone = db.Column(db.String(64), nullable=True)

    check_in = db.Column(db.Date, nullable=False)
    check_out = db.Column(db.Date, nullable=False)

    nights = db.Column(db.Integer, nullable=False, default=1)
    total_amount = db.Column(db.Float, nullable=False, default=0.0)

    status = db.Column(db.String(24), nullable=False, default="pending")  # pending/confirmed/cancelled

    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "shortlet_id": self.shortlet_id,
            "user_id": int(self.user_id) if self.user_id is not None else None,
            "payment_intent_id": int(self.payment_intent_id) if self.payment_intent_id is not None else None,
            "payment_status": self.payment_status or "pending",
            "payment_method": self.payment_method or "wallet",
            "amount_minor": int(self.amount_minor or 0),
            "guest_name": self.guest_name or "",
            "guest_phone": self.guest_phone or "",
            "check_in": self.check_in.isoformat() if self.check_in else None,
            "check_out": self.check_out.isoformat() if self.check_out else None,
            "nights": int(self.nights or 0),
            "total_amount": float(self.total_amount or 0.0),
            "status": self.status or "pending",
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
