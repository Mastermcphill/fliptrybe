"""patch listings image_path and fields

Revision ID: f9a0b1c2d3e4
Revises: f8c9d0e1f2a3
Create Date: 2026-02-09
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

# revision identifiers, used by Alembic.
revision = "f9a0b1c2d3e4"
down_revision = "f8c9d0e1f2a3"
branch_labels = None
depends_on = None


def _add_columns(batch_op, cols, missing):
    for name, col in missing:
        if name not in cols:
            batch_op.add_column(col)


def upgrade():
    bind = op.get_bind()
    insp = inspect(bind)
    if "listings" not in insp.get_table_names():
        return
    cols = {c["name"] for c in insp.get_columns("listings")}
    missing = [
        ("image_path", sa.Column("image_path", sa.String(512), nullable=True)),
        ("seed_key", sa.Column("seed_key", sa.String(64), nullable=True)),
        ("description", sa.Column("description", sa.Text(), nullable=True)),
        ("state", sa.Column("state", sa.String(64), nullable=True)),
        ("city", sa.Column("city", sa.String(64), nullable=True)),
        ("locality", sa.Column("locality", sa.String(64), nullable=True)),
        ("price", sa.Column("price", sa.Float(), nullable=True)),
        ("base_price", sa.Column("base_price", sa.Float(), nullable=True)),
        ("platform_fee", sa.Column("platform_fee", sa.Float(), nullable=True)),
        ("final_price", sa.Column("final_price", sa.Float(), nullable=True)),
        ("is_active", sa.Column("is_active", sa.Boolean(), nullable=True)),
        ("created_at", sa.Column("created_at", sa.DateTime(), nullable=True)),
    ]
    if bind.dialect.name == "sqlite":
        with op.batch_alter_table("listings") as batch_op:
            _add_columns(batch_op, cols, missing)
    else:
        for name, col in missing:
            if name not in cols:
                op.add_column("listings", col)


def downgrade():
    bind = op.get_bind()
    insp = inspect(bind)
    if "listings" not in insp.get_table_names():
        return
    cols = {c["name"] for c in insp.get_columns("listings")}
    to_drop = [n for n in (
        "created_at",
        "is_active",
        "final_price",
        "platform_fee",
        "base_price",
        "price",
        "locality",
        "city",
        "state",
        "description",
        "seed_key",
        "image_path",
    ) if n in cols]
    if not to_drop:
        return
    with op.batch_alter_table("listings") as batch_op:
        for name in to_drop:
            batch_op.drop_column(name)
