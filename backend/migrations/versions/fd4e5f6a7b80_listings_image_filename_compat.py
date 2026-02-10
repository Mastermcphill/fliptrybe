"""listings image filename compat

Revision ID: fd4e5f6a7b80
Revises: fc3d4e5f6a70
Create Date: 2026-02-10 21:40:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "fd4e5f6a7b80"
down_revision = "fc3d4e5f6a70"
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


def upgrade():
    bind = op.get_bind()
    if not _table_exists(bind, "listings"):
        return
    if _column_exists(bind, "listings", "image_filename"):
        return
    with op.batch_alter_table("listings") as batch_op:
        batch_op.add_column(
            sa.Column(
                "image_filename",
                sa.String(length=255),
                nullable=False,
                server_default="",
            )
        )


def downgrade():
    # Drift-safe migration; keep non-destructive downgrade.
    pass

