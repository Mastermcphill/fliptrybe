from datetime import datetime

from app.extensions import db


class Listing(db.Model):
    __tablename__ = "listings"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)

    # Seller/merchant user id (legacy owner_id retained for drifted DBs)
    owner_id = db.Column(db.Integer, nullable=True, index=True)

    title = db.Column(db.String(120), nullable=False)
    description = db.Column(db.Text, nullable=True)
    seed_key = db.Column(db.String(64), nullable=True, unique=True, index=True)

    # Nigeria location filters
    state = db.Column(db.String(64), nullable=True)
    city = db.Column(db.String(64), nullable=True)
    locality = db.Column(db.String(64), nullable=True)

    # Keep float for now (matches your current usage)
    price = db.Column(db.Float, nullable=False, default=0.0)

    # Transparent pricing for merchant listings
    base_price = db.Column(db.Float, nullable=False, default=0.0)
    platform_fee = db.Column(db.Float, nullable=False, default=0.0)
    final_price = db.Column(db.Float, nullable=False, default=0.0)

    # Prefer storing RELATIVE path:
    #   /api/uploads/<filename>
    # Still supports legacy absolute URLs already saved.
    image_path = db.Column(db.String(512), nullable=True)
    is_active = db.Column(db.Boolean, nullable=False, default=True)

    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    def to_dict(self, base_url: str | None = None):
        """
        Returns a dict matching frontend expectations:
          - image: full URL if base_url provided, else stored value
          - image_path: stored value (for compatibility)
        Rules:
          - If stored value is already http/https, return as-is.
          - If stored value is relative (/api/...), build full URL using base_url.
        """
        stored = (self.image_path or "").strip()

        image = stored
        if base_url and stored:
            low = stored.lower()
            if not (low.startswith("http://") or low.startswith("https://")):
                # Ensure leading slash
                path = stored if stored.startswith("/") else f"/{stored}"
                image = f"{base_url.rstrip('/')}{path}"

        base_price = float(self.base_price or 0.0) if self.base_price is not None else 0.0
        platform_fee = float(self.platform_fee or 0.0) if self.platform_fee is not None else 0.0
        final_price = float(self.final_price or 0.0) if self.final_price is not None else 0.0
        if base_price <= 0.0:
            base_price = float(self.price or 0.0)
        if final_price <= 0.0:
            final_price = base_price + platform_fee

        return {
            "id": self.id,
            "user_id": self.user_id,
            "owner_id": self.user_id,
            "state": (self.state or ""),
            "city": (self.city or ""),
            "locality": (self.locality or ""),
            "title": self.title,
            "description": self.description or "",
            "price": float(final_price),
            "base_price": float(base_price),
            "platform_fee": float(platform_fee),
            "final_price": float(final_price),
            "image": image,            # frontend expects this
            "image_path": stored,      # keep raw stored value for compatibility
            "is_active": bool(getattr(self, "is_active", True)),
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
