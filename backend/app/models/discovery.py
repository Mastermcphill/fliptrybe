from datetime import datetime

from app.extensions import db


class ItemDictionary(db.Model):
    __tablename__ = "item_dictionary"

    id = db.Column(db.Integer, primary_key=True)
    term = db.Column(db.String(160), nullable=False, unique=True, index=True)
    category = db.Column(db.String(64), nullable=False, default="general")
    popularity_score = db.Column(db.Integer, nullable=False, default=0)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)


class ListingFavorite(db.Model):
    __tablename__ = "listing_favorites"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    listing_id = db.Column(db.Integer, db.ForeignKey("listings.id"), nullable=False, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint("user_id", "listing_id", name="uq_listing_favorite_user_listing"),
    )


class ShortletFavorite(db.Model):
    __tablename__ = "shortlet_favorites"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    shortlet_id = db.Column(db.Integer, db.ForeignKey("shortlets.id"), nullable=False, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint("user_id", "shortlet_id", name="uq_shortlet_favorite_user_shortlet"),
    )


class ListingView(db.Model):
    __tablename__ = "listing_views"

    id = db.Column(db.Integer, primary_key=True)
    listing_id = db.Column(db.Integer, db.ForeignKey("listings.id"), nullable=False, index=True)
    viewer_user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)
    session_key = db.Column(db.String(128), nullable=False, default="", index=True)
    view_date = db.Column(db.String(10), nullable=False, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint(
            "listing_id",
            "view_date",
            "viewer_user_id",
            "session_key",
            name="uq_listing_view_daily_actor",
        ),
    )


class ShortletView(db.Model):
    __tablename__ = "shortlet_views"

    id = db.Column(db.Integer, primary_key=True)
    shortlet_id = db.Column(db.Integer, db.ForeignKey("shortlets.id"), nullable=False, index=True)
    viewer_user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)
    session_key = db.Column(db.String(128), nullable=False, default="", index=True)
    view_date = db.Column(db.String(10), nullable=False, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint(
            "shortlet_id",
            "view_date",
            "viewer_user_id",
            "session_key",
            name="uq_shortlet_view_daily_actor",
        ),
    )


class CartItem(db.Model):
    __tablename__ = "cart_items"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    listing_id = db.Column(db.Integer, db.ForeignKey("listings.id"), nullable=False, index=True)
    quantity = db.Column(db.Integer, nullable=False, default=1)
    unit_price_minor = db.Column(db.Integer, nullable=False, default=0)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint("user_id", "listing_id", name="uq_cart_item_user_listing"),
    )


class CheckoutBatch(db.Model):
    __tablename__ = "checkout_batches"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    status = db.Column(db.String(32), nullable=False, default="created", index=True)
    payment_method = db.Column(db.String(48), nullable=False, default="wallet")
    total_minor = db.Column(db.Integer, nullable=False, default=0)
    currency = db.Column(db.String(8), nullable=False, default="NGN")
    payment_intent_id = db.Column(db.Integer, db.ForeignKey("payment_intents.id"), nullable=True, index=True)
    order_ids_json = db.Column(db.Text, nullable=False, default="[]")
    idempotency_key = db.Column(db.String(128), nullable=False, default="", index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint("user_id", "idempotency_key", name="uq_checkout_batch_user_key"),
    )


class ShortletMedia(db.Model):
    __tablename__ = "shortlet_media"

    id = db.Column(db.Integer, primary_key=True)
    shortlet_id = db.Column(db.Integer, db.ForeignKey("shortlets.id"), nullable=False, index=True)
    media_type = db.Column(db.String(16), nullable=False, default="image", index=True)
    url = db.Column(db.String(1024), nullable=False, default="")
    thumbnail_url = db.Column(db.String(1024), nullable=True)
    duration_seconds = db.Column(db.Integer, nullable=False, default=0)
    position = db.Column(db.Integer, nullable=False, default=0)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)


class ImageFingerprint(db.Model):
    __tablename__ = "image_fingerprints"

    id = db.Column(db.Integer, primary_key=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)
    hash_type = db.Column(db.String(24), nullable=False, default="phash64")
    hash_hex = db.Column(db.String(32), nullable=False, unique=True, index=True)
    hash_int = db.Column(db.BigInteger, nullable=False, index=True)
    source = db.Column(db.String(32), nullable=False, default="unknown")
    cloudinary_public_id = db.Column(db.String(255), nullable=True, index=True)
    image_url = db.Column(db.String(1024), nullable=False, default="")
    listing_id = db.Column(db.Integer, db.ForeignKey("listings.id"), nullable=True, index=True)
    shortlet_id = db.Column(db.Integer, db.ForeignKey("shortlets.id"), nullable=True, index=True)
    uploader_user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)
