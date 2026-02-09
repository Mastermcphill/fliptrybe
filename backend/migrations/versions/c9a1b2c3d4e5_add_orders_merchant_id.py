"""add orders merchant_id

Revision ID: c9a1b2c3d4e5
Revises: d2f3e4a5b6c7
Create Date: 2026-02-09 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'c9a1b2c3d4e5'
down_revision = 'd2f3e4a5b6c7'
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


def _index_exists(bind, table: str, index: str) -> bool:
    try:
        idx = sa.inspect(bind).get_indexes(table)
        return any(i.get("name") == index for i in idx)
    except Exception:
        return False


def upgrade():
    bind = op.get_bind()
    if not _table_exists(bind, "orders"):
        return

    if not _column_exists(bind, "orders", "merchant_id"):
        with op.batch_alter_table("orders") as batch_op:
            batch_op.add_column(sa.Column("merchant_id", sa.Integer(), nullable=True))

    if _column_exists(bind, "orders", "merchant_id") and not _index_exists(bind, "orders", "ix_orders_merchant_id"):
        op.create_index("ix_orders_merchant_id", "orders", ["merchant_id"])


def downgrade():
    bind = op.get_bind()
    if not _table_exists(bind, "orders"):
        return
    if _index_exists(bind, "orders", "ix_orders_merchant_id"):
        op.drop_index("ix_orders_merchant_id", table_name="orders")
    if _column_exists(bind, "orders", "merchant_id"):
        with op.batch_alter_table("orders") as batch_op:
            batch_op.drop_column("merchant_id")
