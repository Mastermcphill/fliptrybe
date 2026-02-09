"""patch listings city/state/locality

Revision ID: f8c9d0e1f2a3
Revises: f7a8b9c0d1e2
Create Date: 2026-02-09
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

# revision identifiers, used by Alembic.
revision = "f8c9d0e1f2a3"
down_revision = "f7a8b9c0d1e2"
branch_labels = None
depends_on = None


def _add_columns(batch_op, cols, missing):
    for name, coltype in missing:
        if name not in cols:
            batch_op.add_column(sa.Column(name, coltype, nullable=True))


def upgrade():
    bind = op.get_bind()
    insp = inspect(bind)
    if "listings" not in insp.get_table_names():
        return
    cols = {c["name"] for c in insp.get_columns("listings")}
    missing = [
        ("state", sa.String(64)),
        ("city", sa.String(64)),
        ("locality", sa.String(64)),
    ]
    if bind.dialect.name == "sqlite":
        with op.batch_alter_table("listings") as batch_op:
            _add_columns(batch_op, cols, missing)
    else:
        for name, coltype in missing:
            if name not in cols:
                op.add_column("listings", sa.Column(name, coltype, nullable=True))


def downgrade():
    bind = op.get_bind()
    insp = inspect(bind)
    if "listings" not in insp.get_table_names():
        return
    cols = {c["name"] for c in insp.get_columns("listings")}
    to_drop = [name for name in ("locality", "city", "state") if name in cols]
    if not to_drop:
        return
    with op.batch_alter_table("listings") as batch_op:
        for name in to_drop:
            batch_op.drop_column(name)
