"""orders schema parity

Revision ID: d4e5f6a7b8c9
Revises: c9a1b2c3d4e5
Create Date: 2026-02-09 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'd4e5f6a7b8c9'
down_revision = 'c9a1b2c3d4e5'
branch_labels = None
depends_on = None


def _table_exists(bind, name: str) -> bool:
    try:
        return sa.inspect(bind).has_table(name)
    except Exception:
        return False


def _column_exists(bind, table: str, column: str) -> bool:
    try:
        cols = sa.inspect(bind).get_columns(table)
        return any(c.get("name") == column for c in cols)
    except Exception:
        return False


def upgrade():
    bind = op.get_bind()
    if not _table_exists(bind, "orders"):
        return

    columns = [
        ("buyer_id", sa.Column("buyer_id", sa.Integer(), nullable=True)),
        ("merchant_id", sa.Column("merchant_id", sa.Integer(), nullable=True)),
        ("listing_id", sa.Column("listing_id", sa.Integer(), nullable=True)),
        ("amount", sa.Column("amount", sa.Float(), nullable=True)),
        ("delivery_fee", sa.Column("delivery_fee", sa.Float(), nullable=True)),
        ("inspection_fee", sa.Column("inspection_fee", sa.Float(), nullable=True)),
        ("pickup", sa.Column("pickup", sa.String(length=200), nullable=True)),
        ("dropoff", sa.Column("dropoff", sa.String(length=200), nullable=True)),
        ("status", sa.Column("status", sa.String(length=32), nullable=True)),
        ("fulfillment_mode", sa.Column("fulfillment_mode", sa.String(length=16), nullable=True)),
        ("payment_reference", sa.Column("payment_reference", sa.String(length=80), nullable=True)),
        ("seed_key", sa.Column("seed_key", sa.String(length=64), nullable=True)),
        ("driver_id", sa.Column("driver_id", sa.Integer(), nullable=True)),
        ("pickup_code", sa.Column("pickup_code", sa.String(length=8), nullable=True)),
        ("dropoff_code", sa.Column("dropoff_code", sa.String(length=8), nullable=True)),
        ("pickup_code_attempts", sa.Column("pickup_code_attempts", sa.Integer(), nullable=True)),
        ("dropoff_code_attempts", sa.Column("dropoff_code_attempts", sa.Integer(), nullable=True)),
        ("pickup_confirmed_at", sa.Column("pickup_confirmed_at", sa.DateTime(), nullable=True)),
        ("dropoff_confirmed_at", sa.Column("dropoff_confirmed_at", sa.DateTime(), nullable=True)),
        ("created_at", sa.Column("created_at", sa.DateTime(), nullable=True)),
        ("updated_at", sa.Column("updated_at", sa.DateTime(), nullable=True)),
        ("escrow_status", sa.Column("escrow_status", sa.String(length=16), nullable=True)),
        ("escrow_hold_amount", sa.Column("escrow_hold_amount", sa.Float(), nullable=True)),
        ("escrow_currency", sa.Column("escrow_currency", sa.String(length=8), nullable=True)),
        ("escrow_held_at", sa.Column("escrow_held_at", sa.DateTime(), nullable=True)),
        ("escrow_release_at", sa.Column("escrow_release_at", sa.DateTime(), nullable=True)),
        ("escrow_refund_at", sa.Column("escrow_refund_at", sa.DateTime(), nullable=True)),
        ("escrow_disputed_at", sa.Column("escrow_disputed_at", sa.DateTime(), nullable=True)),
        ("release_condition", sa.Column("release_condition", sa.String(length=24), nullable=True)),
        ("release_timeout_hours", sa.Column("release_timeout_hours", sa.Integer(), nullable=True)),
        ("inspection_required", sa.Column("inspection_required", sa.Boolean(), nullable=True)),
        ("inspection_status", sa.Column("inspection_status", sa.String(length=24), nullable=True)),
        ("inspection_outcome", sa.Column("inspection_outcome", sa.String(length=16), nullable=True)),
        ("inspector_id", sa.Column("inspector_id", sa.Integer(), nullable=True)),
        ("inspection_requested_at", sa.Column("inspection_requested_at", sa.DateTime(), nullable=True)),
        ("inspection_on_my_way_at", sa.Column("inspection_on_my_way_at", sa.DateTime(), nullable=True)),
        ("inspection_arrived_at", sa.Column("inspection_arrived_at", sa.DateTime(), nullable=True)),
        ("inspection_inspected_at", sa.Column("inspection_inspected_at", sa.DateTime(), nullable=True)),
        ("inspection_closed_at", sa.Column("inspection_closed_at", sa.DateTime(), nullable=True)),
        ("inspection_evidence_urls", sa.Column("inspection_evidence_urls", sa.Text(), nullable=True)),
        ("inspection_note", sa.Column("inspection_note", sa.String(length=400), nullable=True)),
    ]

    missing = [col for name, col in columns if not _column_exists(bind, "orders", name)]
    if not missing:
        return

    with op.batch_alter_table("orders") as batch_op:
        for col in missing:
            batch_op.add_column(col)


def downgrade():
    # No-op: parity migration should be safe and non-destructive
    pass
