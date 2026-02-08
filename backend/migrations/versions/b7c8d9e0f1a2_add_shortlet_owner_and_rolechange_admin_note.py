"""shortlet owner + role change admin note + moneybox index

Revision ID: b7c8d9e0f1a2
Revises: a3b4c5d6e7f9
Create Date: 2026-02-04 02:15:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'b7c8d9e0f1a2'
down_revision = 'a3b4c5d6e7f9'
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    try:
        return table_name in sa.inspect(op.get_bind()).get_table_names()
    except Exception:
        return False


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


def _fk_exists(table_name: str, fk_name: str) -> bool:
    try:
        fks = [f.get("name") for f in sa.inspect(op.get_bind()).get_foreign_keys(table_name)]
        return fk_name in fks
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
    try:
        op.execute("DROP TABLE IF EXISTS _alembic_tmp_shortlets")
    except Exception:
        pass
    try:
        op.execute("DROP TABLE IF EXISTS _alembic_tmp_orders")
    except Exception:
        pass
    with op.batch_alter_table('shortlets', schema=None) as batch_op:
        _guard_batch_add_column(batch_op, 'shortlets')
        _guard_batch_create_index(batch_op, 'shortlets')
        batch_op.add_column(sa.Column('owner_id', sa.Integer(), nullable=True))
        batch_op.create_index(batch_op.f('ix_shortlets_owner_id'), ['owner_id'], unique=False)
        if not _fk_exists('shortlets', 'fk_shortlets_owner_id_users'):
            batch_op.create_foreign_key('fk_shortlets_owner_id_users', 'users', ['owner_id'], ['id'])

    with op.batch_alter_table('orders', schema=None) as batch_op:
        _guard_batch_add_column(batch_op, 'orders')
        batch_op.add_column(sa.Column('inspection_fee', sa.Float(), nullable=True, server_default='0'))
    try:
        op.execute("UPDATE orders SET inspection_fee = 0 WHERE inspection_fee IS NULL")
    except Exception:
        pass
    with op.batch_alter_table('orders', schema=None) as batch_op:
        batch_op.alter_column('inspection_fee', nullable=False, server_default=None)

    with op.batch_alter_table('role_change_requests', schema=None) as batch_op:
        _guard_batch_add_column(batch_op, 'role_change_requests')
        batch_op.add_column(sa.Column('admin_note', sa.String(length=400), nullable=True))

    with op.batch_alter_table('moneybox_ledger', schema=None) as batch_op:
        _guard_batch_create_index(batch_op, 'moneybox_ledger')
        batch_op.create_index('ix_moneybox_ledger_account_created', ['account_id', 'created_at'], unique=False)


def downgrade():
    with op.batch_alter_table('moneybox_ledger', schema=None) as batch_op:
        batch_op.drop_index('ix_moneybox_ledger_account_created')

    with op.batch_alter_table('role_change_requests', schema=None) as batch_op:
        batch_op.drop_column('admin_note')

    with op.batch_alter_table('orders', schema=None) as batch_op:
        batch_op.drop_column('inspection_fee')

    with op.batch_alter_table('shortlets', schema=None) as batch_op:
        batch_op.drop_constraint('fk_shortlets_owner_id_users', type_='foreignkey')
        batch_op.drop_index(batch_op.f('ix_shortlets_owner_id'))
        batch_op.drop_column('owner_id')
