"""add inspector profile phone

Revision ID: c4d5e6f7a8b9
Revises: b7c8d9e0f1a2
Create Date: 2026-02-04 03:10:00.000000

"""
from alembic import op
import sqlalchemy as sa


revision = "c4d5e6f7a8b9"
down_revision = "b7c8d9e0f1a2"
branch_labels = None
depends_on = None


def _column_exists(table_name: str, column_name: str) -> bool:
    try:
        cols = [c.get("name") for c in sa.inspect(op.get_bind()).get_columns(table_name)]
        return column_name in cols
    except Exception:
        return False


def _index_exists(table_name: str, index_name: str) -> bool:
    try:
        idxs = [i.get("name") for i in sa.inspect(op.get_bind()).get_indexes(table_name)]
        return index_name in idxs
    except Exception:
        return False


def _guard_batch_add_column(batch_op, table_name: str) -> None:
    orig_add = batch_op.add_column

    def _add(col):
        if _column_exists(table_name, col.name):
            return None
        return orig_add(col)

    batch_op.add_column = _add


def _guard_batch_create_index(batch_op, table_name: str) -> None:
    orig_create = batch_op.create_index

    def _create(name, columns, **kw):
        if _index_exists(table_name, name):
            return None
        return orig_create(name, columns, **kw)

    batch_op.create_index = _create


def upgrade():
    with op.batch_alter_table("inspector_profiles", schema=None) as batch_op:
        _guard_batch_add_column(batch_op, "inspector_profiles")
        _guard_batch_create_index(batch_op, "inspector_profiles")
        batch_op.add_column(sa.Column("phone", sa.String(length=32), nullable=True))
        batch_op.create_index(batch_op.f("ix_inspector_profiles_phone"), ["phone"], unique=False)


def downgrade():
    with op.batch_alter_table("inspector_profiles", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_inspector_profiles_phone"))
        batch_op.drop_column("phone")
