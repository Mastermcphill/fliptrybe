"""widen orders varchar(12) columns

Revision ID: fa1b2c3d4e5f
Revises: f9a0b1c2d3e4
Create Date: 2026-02-10
"""

from alembic import op
import re
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "fa1b2c3d4e5f"
down_revision = "f9a0b1c2d3e4"
branch_labels = None
depends_on = None


_SAFE_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _safe_ident(name: str) -> str | None:
    if not name:
        return None
    if not _SAFE_IDENT.match(name):
        return None
    return name


def upgrade():
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        # SQLite does not enforce VARCHAR length in the same way; no-op.
        return

    # Use raw SQL for dynamic drift detection by current schema.
    rows = bind.execute(
        sa.text(
            """
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'orders'
          AND character_maximum_length = 12
          AND data_type IN ('character varying', 'character')
            """
        )
    ).fetchall()

    for row in rows:
        col_name = _safe_ident(getattr(row, "column_name", None) or row[0])
        if not col_name:
            continue
        op.execute(f'ALTER TABLE orders ALTER COLUMN "{col_name}" TYPE VARCHAR(64)')


def downgrade():
    # Intentional no-op: this migration is a drift repair and widening is safe.
    pass
