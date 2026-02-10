"""listings date_posted compat

Revision ID: fe5f6a7b8c90
Revises: fd4e5f6a7b80
Create Date: 2026-02-10 21:45:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "fe5f6a7b8c90"
down_revision = "fd4e5f6a7b80"
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
    if _column_exists(bind, "listings", "date_posted"):
        return
    with op.batch_alter_table("listings") as batch_op:
        batch_op.add_column(
            sa.Column(
                "date_posted",
                sa.DateTime(timezone=True),
                nullable=False,
                server_default=sa.text("CURRENT_TIMESTAMP"),
            )
        )


def downgrade():
    # Drift-safe migration; keep non-destructive downgrade.
    pass

