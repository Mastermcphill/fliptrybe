"""orders total_price parity

Revision ID: fb2c3d4e5f60
Revises: fa1b2c3d4e5f
Create Date: 2026-02-10 13:00:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "fb2c3d4e5f60"
down_revision = "fa1b2c3d4e5f"
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
        return any(c.get("name") == column_name for c in cols)
    except Exception:
        return False


def _ensure_total_price_column(bind) -> None:
    if not _table_exists(bind, "orders"):
        return

    if not _column_exists(bind, "orders", "total_price"):
        with op.batch_alter_table("orders") as batch_op:
            batch_op.add_column(sa.Column("total_price", sa.Float(), nullable=True))

    if not _column_exists(bind, "orders", "total_price"):
        return

    try:
        op.execute("UPDATE orders SET total_price = COALESCE(total_price, amount, 0) WHERE total_price IS NULL")
    except Exception:
        pass

    if bind.dialect.name != "postgresql":
        return

    try:
        op.execute("ALTER TABLE orders ALTER COLUMN total_price SET DEFAULT 0")
    except Exception:
        pass

    try:
        null_count = bind.execute(sa.text("SELECT COUNT(*) FROM orders WHERE total_price IS NULL")).scalar() or 0
        if int(null_count) == 0:
            op.execute("ALTER TABLE orders ALTER COLUMN total_price SET NOT NULL")
    except Exception:
        pass


def upgrade():
    bind = op.get_bind()
    _ensure_total_price_column(bind)


def downgrade():
    # Drift repair migration is intentionally non-destructive.
    pass
