"""account flags and merchant phone

Revision ID: a3b4c5d6e7f9
Revises: f1a9c8d3e2b7
Create Date: 2026-02-04 01:20:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a3b4c5d6e7f9'
down_revision = 'f1a9c8d3e2b7'
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if 'account_flags' not in tables:
        op.create_table(
            'account_flags',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('flag_type', sa.String(length=32), nullable=False),
            sa.Column('signal', sa.String(length=120), nullable=True),
            sa.Column('details', sa.Text(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
            sa.PrimaryKeyConstraint('id')
        )
    try:
        idx = {i['name'] for i in insp.get_indexes('account_flags')}
    except Exception:
        idx = set()
    if 'ix_account_flags_user_id' not in idx:
        with op.batch_alter_table('account_flags', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_account_flags_user_id'), ['user_id'], unique=False)
    if 'ix_account_flags_flag_type' not in idx:
        with op.batch_alter_table('account_flags', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_account_flags_flag_type'), ['flag_type'], unique=False)

    try:
        merchant_cols = {c['name'] for c in insp.get_columns('merchant_profiles')}
    except Exception:
        merchant_cols = set()
    if 'phone' not in merchant_cols:
        with op.batch_alter_table('merchant_profiles', schema=None) as batch_op:
            batch_op.add_column(sa.Column('phone', sa.String(length=32), nullable=True))


def downgrade():
    with op.batch_alter_table('merchant_profiles', schema=None) as batch_op:
        batch_op.drop_column('phone')

    with op.batch_alter_table('account_flags', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_account_flags_flag_type'))
        batch_op.drop_index(batch_op.f('ix_account_flags_user_id'))

    op.drop_table('account_flags')
