from datetime import datetime
import json
import sqlalchemy as sa

from app.extensions import db


class Listing(db.Model):
    __tablename__ = "listings"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)

    # Seller/merchant user id

    title = db.Column(db.String(120), nullable=False)
    description = db.Column(db.Text, nullable=True)
    seed_key = db.Column(db.String(64), nullable=True, unique=True, index=True)

    # Nigeria location filters
    state = db.Column(db.String(64), nullable=True)
    city = db.Column(db.String(64), nullable=True)
    locality = db.Column(db.String(64), nullable=True)

    # Listing category (e.g., declutter)
    category = db.Column(db.String(64), nullable=False, default="declutter", server_default="declutter")
    category_id = db.Column(db.Integer, db.ForeignKey("categories.id"), nullable=True, index=True)
    brand_id = db.Column(db.Integer, db.ForeignKey("brands.id"), nullable=True, index=True)
    model_id = db.Column(db.Integer, db.ForeignKey("brand_models.id"), nullable=True, index=True)
    listing_type = db.Column(db.String(32), nullable=False, default="declutter", server_default="declutter", index=True)

    # Dynamic listing metadata for vertical categories.
    vehicle_metadata = db.Column(db.Text, nullable=True)
    energy_metadata = db.Column(db.Text, nullable=True)
    real_estate_metadata = db.Column(db.Text, nullable=True)

    # Fast filter columns for vehicles, energy, and real estate.
    vehicle_make = db.Column(db.String(80), nullable=True, index=True)
    vehicle_model = db.Column(db.String(80), nullable=True, index=True)
    vehicle_year = db.Column(db.Integer, nullable=True, index=True)
    battery_type = db.Column(db.String(64), nullable=True, index=True)
    inverter_capacity = db.Column(db.String(64), nullable=True, index=True)
    lithium_only = db.Column(db.Boolean, nullable=False, default=False, server_default=sa.text("false"), index=True)
    bundle_badge = db.Column(db.Boolean, nullable=False, default=False, server_default=sa.text("false"))
    property_type = db.Column(db.String(24), nullable=True, index=True)
    bedrooms = db.Column(db.Integer, nullable=True, index=True)
    bathrooms = db.Column(db.Integer, nullable=True, index=True)
    toilets = db.Column(db.Integer, nullable=True)
    parking_spaces = db.Column(db.Integer, nullable=True)
    furnished = db.Column(db.Boolean, nullable=True, index=True)
    serviced = db.Column(db.Boolean, nullable=True, index=True)
    land_size = db.Column(db.Float, nullable=True, index=True)
    title_document_type = db.Column(db.String(64), nullable=True, index=True)

    # Buyer trust and fulfillment flags.
    delivery_available = db.Column(db.Boolean, nullable=True)
    inspection_required = db.Column(db.Boolean, nullable=True)
    location_verified = db.Column(db.Boolean, nullable=False, default=False, server_default=sa.text("false"))
    inspection_request_enabled = db.Column(db.Boolean, nullable=False, default=False, server_default=sa.text("false"))
    financing_option = db.Column(db.Boolean, nullable=False, default=False, server_default=sa.text("false"))

    # Admin review workflow for high-value verticals.
    approval_status = db.Column(db.String(24), nullable=False, default="approved", server_default="approved", index=True)
    inspection_flagged = db.Column(db.Boolean, nullable=False, default=False, server_default=sa.text("false"), index=True)

    # Merchant-only customer payout profile (private).
    customer_payout_profile_json = db.Column(db.Text, nullable=True)
    customer_profile_updated_at = db.Column(db.DateTime(timezone=True), nullable=True)
    customer_profile_updated_by = db.Column(db.Integer, nullable=True)

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
    image_filename = db.Column(db.String(255), nullable=False, default="", server_default="")
    is_active = db.Column(db.Boolean, nullable=False, default=True)
    views_count = db.Column(db.Integer, nullable=False, default=0, server_default="0")
    favorites_count = db.Column(db.Integer, nullable=False, default=0, server_default="0")
    heat_level = db.Column(db.String(16), nullable=False, default="normal", server_default="normal")
    heat_score = db.Column(db.Integer, nullable=False, default=0, server_default="0")

    created_at = db.Column(db.DateTime(timezone=True), nullable=False, default=datetime.utcnow, server_default=sa.func.now())
    date_posted = db.Column(db.DateTime(timezone=True), nullable=False, default=datetime.utcnow, server_default=sa.func.now())

    @property
    def owner_id(self):
        # Backwards-compatible alias for older clients; not a DB column.
        return self.user_id

    @owner_id.setter
    def owner_id(self, value):
        # Map legacy assignments to user_id.
        self.user_id = value

    def to_dict(self, base_url: str | None = None, *, include_private: bool = False):
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

        def _parse_meta(raw_value):
            text_value = str(raw_value or "").strip()
            if not text_value:
                return {}
            try:
                parsed = json.loads(text_value)
                if isinstance(parsed, dict):
                    return parsed
            except Exception:
                return {}
            return {}

        vehicle_meta = _parse_meta(getattr(self, "vehicle_metadata", None))
        energy_meta = _parse_meta(getattr(self, "energy_metadata", None))
        real_estate_meta = _parse_meta(getattr(self, "real_estate_metadata", None))
        payout_profile = _parse_meta(getattr(self, "customer_payout_profile_json", None))

        payload = {
            "id": self.id,
            "user_id": self.user_id,
            "owner_id": self.user_id,
            "state": (self.state or ""),
            "city": (self.city or ""),
            "locality": (self.locality or ""),
            "category": (getattr(self, "category", None) or ""),
            "category_id": int(getattr(self, "category_id", 0)) if getattr(self, "category_id", None) is not None else None,
            "brand_id": int(getattr(self, "brand_id", 0)) if getattr(self, "brand_id", None) is not None else None,
            "model_id": int(getattr(self, "model_id", 0)) if getattr(self, "model_id", None) is not None else None,
            "listing_type": (getattr(self, "listing_type", None) or "declutter"),
            "title": self.title,
            "description": self.description or "",
            "price": float(final_price),
            "base_price": float(base_price),
            "platform_fee": float(platform_fee),
            "final_price": float(final_price),
            "image": image,            # frontend expects this
            "image_path": stored,      # keep raw stored value for compatibility
            "image_filename": getattr(self, "image_filename", "") or "",
            "is_active": bool(getattr(self, "is_active", True)),
            "views_count": int(getattr(self, "views_count", 0) or 0),
            "favorites_count": int(getattr(self, "favorites_count", 0) or 0),
            "heat_level": (getattr(self, "heat_level", "normal") or "normal"),
            "heat_score": int(getattr(self, "heat_score", 0) or 0),
            "vehicle_metadata": vehicle_meta,
            "energy_metadata": energy_meta,
            "real_estate_metadata": real_estate_meta,
            "vehicle_make": (getattr(self, "vehicle_make", None) or ""),
            "vehicle_model": (getattr(self, "vehicle_model", None) or ""),
            "vehicle_year": int(getattr(self, "vehicle_year", 0)) if getattr(self, "vehicle_year", None) is not None else None,
            "battery_type": (getattr(self, "battery_type", None) or ""),
            "inverter_capacity": (getattr(self, "inverter_capacity", None) or ""),
            "lithium_only": bool(getattr(self, "lithium_only", False)),
            "bundle_badge": bool(getattr(self, "bundle_badge", False)),
            "property_type": (getattr(self, "property_type", None) or ""),
            "bedrooms": int(getattr(self, "bedrooms", 0)) if getattr(self, "bedrooms", None) is not None else None,
            "bathrooms": int(getattr(self, "bathrooms", 0)) if getattr(self, "bathrooms", None) is not None else None,
            "toilets": int(getattr(self, "toilets", 0)) if getattr(self, "toilets", None) is not None else None,
            "parking_spaces": int(getattr(self, "parking_spaces", 0)) if getattr(self, "parking_spaces", None) is not None else None,
            "furnished": bool(getattr(self, "furnished", False)),
            "serviced": bool(getattr(self, "serviced", False)),
            "land_size": float(getattr(self, "land_size", 0.0)) if getattr(self, "land_size", None) is not None else None,
            "title_document_type": (getattr(self, "title_document_type", None) or ""),
            "delivery_available": bool(getattr(self, "delivery_available", False)),
            "inspection_required": bool(getattr(self, "inspection_required", False)),
            "location_verified": bool(getattr(self, "location_verified", False)),
            "inspection_request_enabled": bool(getattr(self, "inspection_request_enabled", False)),
            "financing_option": bool(getattr(self, "financing_option", False)),
            "approval_status": (getattr(self, "approval_status", None) or "approved"),
            "inspection_flagged": bool(getattr(self, "inspection_flagged", False)),
            "date_posted": self.date_posted.isoformat() if getattr(self, "date_posted", None) else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
        if include_private:
            payload["customer_payout_profile"] = payout_profile
            payload["customer_profile_updated_at"] = (
                self.customer_profile_updated_at.isoformat()
                if getattr(self, "customer_profile_updated_at", None)
                else None
            )
            payload["customer_profile_updated_by"] = int(self.customer_profile_updated_by) if getattr(self, "customer_profile_updated_by", None) is not None else None
        return payload
