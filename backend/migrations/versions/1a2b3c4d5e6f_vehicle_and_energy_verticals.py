"""vehicle and energy vertical expansion

Revision ID: 1a2b3c4d5e6f
Revises: 0f1e2d3c4b5a
Create Date: 2026-02-18 11:15:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "1a2b3c4d5e6f"
down_revision = "0f1e2d3c4b5a"
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
    if not _column_exists(bind, "listings", "listing_type"):
        to_add.append(sa.Column("listing_type", sa.String(length=32), nullable=False, server_default="declutter"))
    if not _column_exists(bind, "listings", "vehicle_metadata"):
        to_add.append(sa.Column("vehicle_metadata", sa.Text(), nullable=True))
    if not _column_exists(bind, "listings", "energy_metadata"):
        to_add.append(sa.Column("energy_metadata", sa.Text(), nullable=True))
    if not _column_exists(bind, "listings", "vehicle_make"):
        to_add.append(sa.Column("vehicle_make", sa.String(length=80), nullable=True))
    if not _column_exists(bind, "listings", "vehicle_model"):
        to_add.append(sa.Column("vehicle_model", sa.String(length=80), nullable=True))
    if not _column_exists(bind, "listings", "vehicle_year"):
        to_add.append(sa.Column("vehicle_year", sa.Integer(), nullable=True))
    if not _column_exists(bind, "listings", "battery_type"):
        to_add.append(sa.Column("battery_type", sa.String(length=64), nullable=True))
    if not _column_exists(bind, "listings", "inverter_capacity"):
        to_add.append(sa.Column("inverter_capacity", sa.String(length=64), nullable=True))
    if not _column_exists(bind, "listings", "lithium_only"):
        to_add.append(sa.Column("lithium_only", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists(bind, "listings", "bundle_badge"):
        to_add.append(sa.Column("bundle_badge", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists(bind, "listings", "delivery_available"):
        to_add.append(sa.Column("delivery_available", sa.Boolean(), nullable=True))
    if not _column_exists(bind, "listings", "inspection_required"):
        to_add.append(sa.Column("inspection_required", sa.Boolean(), nullable=True))
    if not _column_exists(bind, "listings", "location_verified"):
        to_add.append(sa.Column("location_verified", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists(bind, "listings", "inspection_request_enabled"):
        to_add.append(sa.Column("inspection_request_enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists(bind, "listings", "financing_option"):
        to_add.append(sa.Column("financing_option", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists(bind, "listings", "approval_status"):
        to_add.append(sa.Column("approval_status", sa.String(length=24), nullable=False, server_default="approved"))
    if not _column_exists(bind, "listings", "inspection_flagged"):
        to_add.append(sa.Column("inspection_flagged", sa.Boolean(), nullable=False, server_default=sa.text("false")))

    if to_add:
        with op.batch_alter_table("listings") as batch_op:
            for col in to_add:
                batch_op.add_column(col)

    if not _index_exists(bind, "listings", "ix_listings_listing_type"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_listing_type", ["listing_type"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_vehicle_make"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_vehicle_make", ["vehicle_make"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_vehicle_model"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_vehicle_model", ["vehicle_model"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_vehicle_year"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_vehicle_year", ["vehicle_year"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_battery_type"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_battery_type", ["battery_type"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_inverter_capacity"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_inverter_capacity", ["inverter_capacity"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_lithium_only"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_lithium_only", ["lithium_only"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_approval_status"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_approval_status", ["approval_status"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_inspection_flagged"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index("ix_listings_inspection_flagged", ["inspection_flagged"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_make_model_year"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index(
                "ix_listings_make_model_year",
                ["vehicle_make", "vehicle_model", "vehicle_year"],
                unique=False,
            )
    if not _index_exists(bind, "listings", "ix_listings_energy_filter_triplet"):
        with op.batch_alter_table("listings") as batch_op:
            batch_op.create_index(
                "ix_listings_energy_filter_triplet",
                ["battery_type", "inverter_capacity", "lithium_only"],
                unique=False,
            )

    try:
        op.execute(sa.text("UPDATE listings SET listing_type='declutter' WHERE listing_type IS NULL OR listing_type=''"))
        op.execute(sa.text("UPDATE listings SET approval_status='approved' WHERE approval_status IS NULL OR approval_status=''"))
    except Exception:
        pass


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


def _seed_vertical_categories(bind) -> None:
    if not _table_exists(bind, "categories"):
        return

    vehicles_root = _upsert_category(bind, name="Vehicles", slug="vehicles", parent_id=None, sort_order=200)
    power_root = _upsert_category(bind, name="Power & Energy", slug="power-energy", parent_id=None, sort_order=201)

    if vehicles_root is not None:
        leaves = [
            ("Cars", "cars"),
            ("Buses & Microbuses", "buses-microbuses"),
            ("Trucks & Trailers", "trucks-trailers"),
            ("Motorcycles & Scooters", "motorcycles-scooters"),
            ("Construction & Heavy Machinery", "construction-heavy-machinery"),
            ("Watercraft & Boats", "watercraft-boats"),
            ("Vehicle Parts & Accessories", "vehicle-parts-accessories"),
        ]
        for idx, (name, slug) in enumerate(leaves):
            _upsert_category(
                bind,
                name=name,
                slug=slug,
                parent_id=int(vehicles_root),
                sort_order=idx,
            )

    if power_root is not None:
        leaves = [
            ("Inverters", "inverters"),
            ("Solar Panels", "solar-panels"),
            ("Solar Batteries", "solar-batteries"),
            ("Lithium Batteries", "lithium-batteries"),
            ("LiFePO4 Batteries", "lifepo4-batteries"),
            ("Gel Batteries", "gel-batteries"),
            ("Tall Tubular Batteries", "tall-tubular-batteries"),
            ("Charge Controllers", "charge-controllers"),
            ("Solar Accessories", "solar-accessories"),
            ("Solar Installation Services", "solar-installation-services"),
            ("Solar Bundle", "solar-bundle"),
        ]
        for idx, (name, slug) in enumerate(leaves):
            _upsert_category(
                bind,
                name=name,
                slug=slug,
                parent_id=int(power_root),
                sort_order=idx,
            )


def upgrade():
    bind = op.get_bind()
    _add_listing_columns(bind)
    _seed_vertical_categories(bind)


def downgrade():
    # Non-destructive downgrade.
    pass

