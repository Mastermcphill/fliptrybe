"""super mega discovery cart media

Revision ID: b2c3d4e5f602
Revises: b1c2d3e4f501
Create Date: 2026-02-12 18:20:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "b2c3d4e5f602"
down_revision = "b1c2d3e4f501"
branch_labels = None
depends_on = None


def _table_exists(bind, table_name: str) -> bool:
    try:
        return sa.inspect(bind).has_table(table_name)
    except Exception:
        return False


def _column_exists(bind, table_name: str, column_name: str) -> bool:
    try:
        cols = sa.inspect(bind).get_columns(table_name)
        return any((c.get("name") or "") == column_name for c in cols)
    except Exception:
        return False


def _index_exists(bind, table_name: str, index_name: str) -> bool:
    try:
        rows = sa.inspect(bind).get_indexes(table_name)
        return any((r.get("name") or "") == index_name for r in rows)
    except Exception:
        return False


def _add_user_settings_columns(bind):
    if not _table_exists(bind, "user_settings"):
        return
    add = []
    if not _column_exists(bind, "user_settings", "preferred_city"):
        add.append(sa.Column("preferred_city", sa.String(length=80), nullable=True))
    if not _column_exists(bind, "user_settings", "preferred_state"):
        add.append(sa.Column("preferred_state", sa.String(length=80), nullable=True))
    if add:
        with op.batch_alter_table("user_settings") as batch:
            for col in add:
                batch.add_column(col)


def _add_autopilot_flags(bind):
    if not _table_exists(bind, "autopilot_settings"):
        return
    add = []
    if not _column_exists(bind, "autopilot_settings", "city_discovery_v1"):
        add.append(sa.Column("city_discovery_v1", sa.Boolean(), nullable=False, server_default=sa.text("true")))
    if not _column_exists(bind, "autopilot_settings", "views_heat_v1"):
        add.append(sa.Column("views_heat_v1", sa.Boolean(), nullable=False, server_default=sa.text("true")))
    if not _column_exists(bind, "autopilot_settings", "cart_checkout_v1"):
        add.append(sa.Column("cart_checkout_v1", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists(bind, "autopilot_settings", "shortlet_reels_v1"):
        add.append(sa.Column("shortlet_reels_v1", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists(bind, "autopilot_settings", "watcher_notifications_v1"):
        add.append(sa.Column("watcher_notifications_v1", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if add:
        with op.batch_alter_table("autopilot_settings") as batch:
            for col in add:
                batch.add_column(col)


def _add_listing_columns(bind):
    if not _table_exists(bind, "listings"):
        return
    add = []
    if not _column_exists(bind, "listings", "views_count"):
        add.append(sa.Column("views_count", sa.Integer(), nullable=False, server_default="0"))
    if not _column_exists(bind, "listings", "favorites_count"):
        add.append(sa.Column("favorites_count", sa.Integer(), nullable=False, server_default="0"))
    if not _column_exists(bind, "listings", "heat_level"):
        add.append(sa.Column("heat_level", sa.String(length=16), nullable=False, server_default="normal"))
    if not _column_exists(bind, "listings", "heat_score"):
        add.append(sa.Column("heat_score", sa.Integer(), nullable=False, server_default="0"))
    if add:
        with op.batch_alter_table("listings") as batch:
            for col in add:
                batch.add_column(col)


def _add_shortlet_columns(bind):
    if not _table_exists(bind, "shortlets"):
        return
    add = []
    if not _column_exists(bind, "shortlets", "views_count"):
        add.append(sa.Column("views_count", sa.Integer(), nullable=False, server_default="0"))
    if not _column_exists(bind, "shortlets", "favorites_count"):
        add.append(sa.Column("favorites_count", sa.Integer(), nullable=False, server_default="0"))
    if not _column_exists(bind, "shortlets", "heat_level"):
        add.append(sa.Column("heat_level", sa.String(length=16), nullable=False, server_default="normal"))
    if not _column_exists(bind, "shortlets", "heat_score"):
        add.append(sa.Column("heat_score", sa.Integer(), nullable=False, server_default="0"))
    if add:
        with op.batch_alter_table("shortlets") as batch:
            for col in add:
                batch.add_column(col)


def _add_payment_intent_columns(bind):
    if not _table_exists(bind, "payment_intents"):
        return
    if not _column_exists(bind, "payment_intents", "amount_minor"):
        with op.batch_alter_table("payment_intents") as batch:
            batch.add_column(sa.Column("amount_minor", sa.Integer(), nullable=True))
    if not _index_exists(bind, "payment_intents", "ix_payment_intents_amount_minor"):
        with op.batch_alter_table("payment_intents") as batch:
            batch.create_index("ix_payment_intents_amount_minor", ["amount_minor"], unique=False)


def _add_shortlet_booking_columns(bind):
    if not _table_exists(bind, "shortlet_bookings"):
        return
    add = []
    if not _column_exists(bind, "shortlet_bookings", "user_id"):
        add.append(sa.Column("user_id", sa.Integer(), nullable=True))
    if not _column_exists(bind, "shortlet_bookings", "payment_intent_id"):
        add.append(sa.Column("payment_intent_id", sa.Integer(), nullable=True))
    if not _column_exists(bind, "shortlet_bookings", "payment_status"):
        add.append(sa.Column("payment_status", sa.String(length=32), nullable=False, server_default="pending"))
    if not _column_exists(bind, "shortlet_bookings", "payment_method"):
        add.append(sa.Column("payment_method", sa.String(length=48), nullable=False, server_default="wallet"))
    if not _column_exists(bind, "shortlet_bookings", "amount_minor"):
        add.append(sa.Column("amount_minor", sa.Integer(), nullable=False, server_default="0"))
    if add:
        with op.batch_alter_table("shortlet_bookings") as batch:
            for col in add:
                batch.add_column(col)
    try:
        if not _index_exists(bind, "shortlet_bookings", "ix_shortlet_bookings_user_id"):
            with op.batch_alter_table("shortlet_bookings") as batch:
                batch.create_index("ix_shortlet_bookings_user_id", ["user_id"], unique=False)
    except Exception:
        pass
    try:
        if not _index_exists(bind, "shortlet_bookings", "ix_shortlet_bookings_payment_intent_id"):
            with op.batch_alter_table("shortlet_bookings") as batch:
                batch.create_index("ix_shortlet_bookings_payment_intent_id", ["payment_intent_id"], unique=False)
    except Exception:
        pass


def _create_discovery_tables(bind):
    if not _table_exists(bind, "item_dictionary"):
        op.create_table(
            "item_dictionary",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("term", sa.String(length=160), nullable=False),
            sa.Column("category", sa.String(length=64), nullable=False, server_default="general"),
            sa.Column("popularity_score", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("term", name="uq_item_dictionary_term"),
        )
        op.create_index("ix_item_dictionary_term", "item_dictionary", ["term"], unique=False)

    if not _table_exists(bind, "listing_favorites"):
        op.create_table(
            "listing_favorites",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("listing_id", sa.Integer(), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("user_id", "listing_id", name="uq_listing_favorite_user_listing"),
        )
        op.create_index("ix_listing_favorites_user_id", "listing_favorites", ["user_id"], unique=False)
        op.create_index("ix_listing_favorites_listing_id", "listing_favorites", ["listing_id"], unique=False)

    if not _table_exists(bind, "shortlet_favorites"):
        op.create_table(
            "shortlet_favorites",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("shortlet_id", sa.Integer(), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("user_id", "shortlet_id", name="uq_shortlet_favorite_user_shortlet"),
        )
        op.create_index("ix_shortlet_favorites_user_id", "shortlet_favorites", ["user_id"], unique=False)
        op.create_index("ix_shortlet_favorites_shortlet_id", "shortlet_favorites", ["shortlet_id"], unique=False)

    if not _table_exists(bind, "listing_views"):
        op.create_table(
            "listing_views",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("listing_id", sa.Integer(), nullable=False),
            sa.Column("viewer_user_id", sa.Integer(), nullable=True),
            sa.Column("session_key", sa.String(length=128), nullable=False, server_default=""),
            sa.Column("view_date", sa.String(length=10), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint(
                "listing_id",
                "view_date",
                "viewer_user_id",
                "session_key",
                name="uq_listing_view_daily_actor",
            ),
        )
        op.create_index("ix_listing_views_listing_id", "listing_views", ["listing_id"], unique=False)
        op.create_index("ix_listing_views_viewer_user_id", "listing_views", ["viewer_user_id"], unique=False)
        op.create_index("ix_listing_views_session_key", "listing_views", ["session_key"], unique=False)
        op.create_index("ix_listing_views_view_date", "listing_views", ["view_date"], unique=False)

    if not _table_exists(bind, "shortlet_views"):
        op.create_table(
            "shortlet_views",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("shortlet_id", sa.Integer(), nullable=False),
            sa.Column("viewer_user_id", sa.Integer(), nullable=True),
            sa.Column("session_key", sa.String(length=128), nullable=False, server_default=""),
            sa.Column("view_date", sa.String(length=10), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint(
                "shortlet_id",
                "view_date",
                "viewer_user_id",
                "session_key",
                name="uq_shortlet_view_daily_actor",
            ),
        )
        op.create_index("ix_shortlet_views_shortlet_id", "shortlet_views", ["shortlet_id"], unique=False)
        op.create_index("ix_shortlet_views_viewer_user_id", "shortlet_views", ["viewer_user_id"], unique=False)
        op.create_index("ix_shortlet_views_session_key", "shortlet_views", ["session_key"], unique=False)
        op.create_index("ix_shortlet_views_view_date", "shortlet_views", ["view_date"], unique=False)

    if not _table_exists(bind, "cart_items"):
        op.create_table(
            "cart_items",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("listing_id", sa.Integer(), nullable=False),
            sa.Column("quantity", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("unit_price_minor", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("user_id", "listing_id", name="uq_cart_item_user_listing"),
        )
        op.create_index("ix_cart_items_user_id", "cart_items", ["user_id"], unique=False)
        op.create_index("ix_cart_items_listing_id", "cart_items", ["listing_id"], unique=False)

    if not _table_exists(bind, "checkout_batches"):
        op.create_table(
            "checkout_batches",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("status", sa.String(length=32), nullable=False, server_default="created"),
            sa.Column("payment_method", sa.String(length=48), nullable=False, server_default="wallet"),
            sa.Column("total_minor", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("currency", sa.String(length=8), nullable=False, server_default="NGN"),
            sa.Column("payment_intent_id", sa.Integer(), nullable=True),
            sa.Column("order_ids_json", sa.Text(), nullable=False, server_default="[]"),
            sa.Column("idempotency_key", sa.String(length=128), nullable=False, server_default=""),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("user_id", "idempotency_key", name="uq_checkout_batch_user_key"),
        )
        op.create_index("ix_checkout_batches_user_id", "checkout_batches", ["user_id"], unique=False)
        op.create_index("ix_checkout_batches_payment_intent_id", "checkout_batches", ["payment_intent_id"], unique=False)
        op.create_index("ix_checkout_batches_idempotency_key", "checkout_batches", ["idempotency_key"], unique=False)

    if not _table_exists(bind, "shortlet_media"):
        op.create_table(
            "shortlet_media",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("shortlet_id", sa.Integer(), nullable=False),
            sa.Column("media_type", sa.String(length=16), nullable=False, server_default="image"),
            sa.Column("url", sa.String(length=1024), nullable=False, server_default=""),
            sa.Column("thumbnail_url", sa.String(length=1024), nullable=True),
            sa.Column("duration_seconds", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), nullable=False),
        )
        op.create_index("ix_shortlet_media_shortlet_id", "shortlet_media", ["shortlet_id"], unique=False)
        op.create_index("ix_shortlet_media_media_type", "shortlet_media", ["media_type"], unique=False)


def _seed_item_dictionary():
    bind = op.get_bind()
    terms = [
        ("PS4", "electronics", 100),
        ("PS5", "electronics", 99),
        ("Smart TV", "electronics", 98),
        ("Generator", "home", 97),
        ("Sofa set", "furniture", 96),
        ("Dining table", "furniture", 95),
        ("TV console", "furniture", 94),
        ("iPhone", "phones", 93),
        ("Laptop", "computers", 92),
        ("Fridge", "appliances", 91),
        ("Washing machine", "appliances", 90),
    ]
    for term, category, score in terms:
        try:
            bind.execute(
                sa.text(
                    "INSERT INTO item_dictionary(term, category, popularity_score, created_at, updated_at) "
                    "SELECT :term, :category, :score, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP "
                    "WHERE NOT EXISTS (SELECT 1 FROM item_dictionary WHERE lower(term)=lower(:term))"
                ),
                {"term": term, "category": category, "score": score},
            )
        except Exception:
            pass


def upgrade():
    bind = op.get_bind()
    _add_user_settings_columns(bind)
    _add_autopilot_flags(bind)
    _add_listing_columns(bind)
    _add_shortlet_columns(bind)
    _add_payment_intent_columns(bind)
    _add_shortlet_booking_columns(bind)
    _create_discovery_tables(bind)
    _seed_item_dictionary()


def downgrade():
    # Non-destructive downgrade: keep compatibility columns/tables.
    pass
