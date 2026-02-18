"""omega commerce real estate and saved searches

Revision ID: 2f3a4b5c6d7e
Revises: 1a2b3c4d5e6f
Create Date: 2026-02-18 17:30:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "2f3a4b5c6d7e"
down_revision = "1a2b3c4d5e6f"
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
        return any((col.get("name") or "") == column_name for col in cols)
    except Exception:
        return False


def _index_exists(bind, table_name: str, index_name: str) -> bool:
    try:
        indexes = sa.inspect(bind).get_indexes(table_name)
        return any((idx.get("name") or "") == index_name for idx in indexes)
    except Exception:
        return False


def _add_listing_columns(bind) -> None:
    if not _table_exists(bind, "listings"):
        return
    to_add: list[sa.Column] = []
    if not _column_exists(bind, "listings", "real_estate_metadata"):
        to_add.append(sa.Column("real_estate_metadata", sa.Text(), nullable=True))
    if not _column_exists(bind, "listings", "property_type"):
        to_add.append(sa.Column("property_type", sa.String(length=24), nullable=True))
    if not _column_exists(bind, "listings", "bedrooms"):
        to_add.append(sa.Column("bedrooms", sa.Integer(), nullable=True))
    if not _column_exists(bind, "listings", "bathrooms"):
        to_add.append(sa.Column("bathrooms", sa.Integer(), nullable=True))
    if not _column_exists(bind, "listings", "toilets"):
        to_add.append(sa.Column("toilets", sa.Integer(), nullable=True))
    if not _column_exists(bind, "listings", "parking_spaces"):
        to_add.append(sa.Column("parking_spaces", sa.Integer(), nullable=True))
    if not _column_exists(bind, "listings", "furnished"):
        to_add.append(sa.Column("furnished", sa.Boolean(), nullable=True))
    if not _column_exists(bind, "listings", "serviced"):
        to_add.append(sa.Column("serviced", sa.Boolean(), nullable=True))
    if not _column_exists(bind, "listings", "land_size"):
        to_add.append(sa.Column("land_size", sa.Float(), nullable=True))
    if not _column_exists(bind, "listings", "title_document_type"):
        to_add.append(sa.Column("title_document_type", sa.String(length=64), nullable=True))
    if not _column_exists(bind, "listings", "customer_payout_profile_json"):
        to_add.append(sa.Column("customer_payout_profile_json", sa.Text(), nullable=True))
    if not _column_exists(bind, "listings", "customer_profile_updated_at"):
        to_add.append(sa.Column("customer_profile_updated_at", sa.DateTime(timezone=True), nullable=True))
    if not _column_exists(bind, "listings", "customer_profile_updated_by"):
        to_add.append(sa.Column("customer_profile_updated_by", sa.Integer(), nullable=True))

    if to_add:
        with op.batch_alter_table("listings") as batch_op:
            for col in to_add:
                batch_op.add_column(col)

    if not _index_exists(bind, "listings", "ix_listings_property_type"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_property_type", ["property_type"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_bedrooms"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_bedrooms", ["bedrooms"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_bathrooms"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_bathrooms", ["bathrooms"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_furnished"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_furnished", ["furnished"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_serviced"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_serviced", ["serviced"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_land_size"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_land_size", ["land_size"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_title_document_type"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_title_document_type", ["title_document_type"], unique=False)


def _add_support_message_columns(bind) -> None:
    if not _table_exists(bind, "support_messages"):
        return
    cols: list[sa.Column] = []
    if not _column_exists(bind, "support_messages", "recipient_id"):
        cols.append(sa.Column("recipient_id", sa.Integer(), nullable=True))
    if not _column_exists(bind, "support_messages", "listing_id"):
        cols.append(sa.Column("listing_id", sa.Integer(), nullable=True))
    if cols:
        with op.batch_alter_table("support_messages") as batch_op:
            for col in cols:
                batch_op.add_column(col)
    if not _index_exists(bind, "support_messages", "ix_support_messages_recipient_id"):
        with op.batch_alter_table("support_messages") as batch_op:
            batch_op.create_index("ix_support_messages_recipient_id", ["recipient_id"], unique=False)
    if not _index_exists(bind, "support_messages", "ix_support_messages_listing_id"):
        with op.batch_alter_table("support_messages") as batch_op:
            batch_op.create_index("ix_support_messages_listing_id", ["listing_id"], unique=False)


def _create_saved_searches(bind) -> None:
    if _table_exists(bind, "saved_searches"):
        return
    op.create_table(
        "saved_searches",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("vertical", sa.String(length=32), nullable=False, server_default="marketplace"),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("query_json", sa.Text(), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    with op.batch_alter_table("saved_searches") as batch_op:
        batch_op.create_index("ix_saved_searches_user_id", ["user_id"], unique=False)
        batch_op.create_index("ix_saved_searches_vertical", ["vertical"], unique=False)
        batch_op.create_index("ix_saved_searches_user_vertical_created", ["user_id", "vertical", "created_at"], unique=False)


def _upsert_category(bind, *, name: str, slug: str, parent_id: int | None, sort_order: int) -> int | None:
    current_id = bind.execute(
        sa.text("SELECT id FROM categories WHERE lower(slug)=lower(:slug)"),
        {"slug": slug},
    ).scalar()
    if current_id is None:
        bind.execute(
            sa.text(
                "INSERT INTO categories(name, slug, parent_id, sort_order, is_active, created_at, updated_at) "
                "VALUES(:name, :slug, :parent_id, :sort_order, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
            ),
            {"name": name, "slug": slug, "parent_id": parent_id, "sort_order": sort_order},
        )
        current_id = bind.execute(
            sa.text("SELECT id FROM categories WHERE lower(slug)=lower(:slug)"),
            {"slug": slug},
        ).scalar()
    else:
        bind.execute(
            sa.text(
                "UPDATE categories "
                "SET name=:name, parent_id=:parent_id, sort_order=:sort_order, is_active=true, updated_at=CURRENT_TIMESTAMP "
                "WHERE id=:id"
            ),
            {"id": int(current_id), "name": name, "parent_id": parent_id, "sort_order": sort_order},
        )
    return int(current_id) if current_id is not None else None


def _seed_real_estate_categories(bind) -> None:
    if not _table_exists(bind, "categories"):
        return
    root_id = _upsert_category(bind, name="Real Estate", slug="real-estate", parent_id=None, sort_order=202)
    if root_id is None:
        return
    leaves = [
        ("House for Rent", "house-for-rent"),
        ("House for Sale", "house-for-sale"),
        ("Land for Sale", "land-for-sale"),
    ]
    for idx, (name, slug) in enumerate(leaves):
        _upsert_category(
            bind,
            name=name,
            slug=slug,
            parent_id=int(root_id),
            sort_order=idx,
        )


def upgrade():
    bind = op.get_bind()
    _add_listing_columns(bind)
    _add_support_message_columns(bind)
    _create_saved_searches(bind)
    _seed_real_estate_categories(bind)


def downgrade():
    # Non-destructive downgrade.
    pass

