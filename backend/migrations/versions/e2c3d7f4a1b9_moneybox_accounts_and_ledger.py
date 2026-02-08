"""moneybox accounts and ledger

Revision ID: e2c3d7f4a1b9
Revises: b5f7e2d8c1a4
Create Date: 2026-02-04 11:05:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'e2c3d7f4a1b9'
down_revision = 'b5f7e2d8c1a4'
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if 'moneybox_accounts' not in tables:
        op.create_table(
            'moneybox_accounts',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('tier', sa.Integer(), nullable=False),
            sa.Column('status', sa.String(length=16), nullable=False),
            sa.Column('principal_balance', sa.Float(), nullable=False),
            sa.Column('bonus_balance', sa.Float(), nullable=False),
            sa.Column('lock_days', sa.Integer(), nullable=False),
            sa.Column('lock_start_at', sa.DateTime(), nullable=True),
            sa.Column('auto_open_at', sa.DateTime(), nullable=True),
            sa.Column('maturity_at', sa.DateTime(), nullable=True),
            sa.Column('autosave_enabled', sa.Boolean(), nullable=False),
            sa.Column('autosave_percent', sa.Float(), nullable=False),
            sa.Column('bonus_eligible', sa.Boolean(), nullable=False),
            sa.Column('bonus_awarded_at', sa.DateTime(), nullable=True),
            sa.Column('last_withdraw_at', sa.DateTime(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('user_id')
        )
    try:
        idx_accounts = {i['name'] for i in insp.get_indexes('moneybox_accounts')}
    except Exception:
        idx_accounts = set()
    if 'ix_moneybox_accounts_user_id' not in idx_accounts:
        with op.batch_alter_table('moneybox_accounts', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_moneybox_accounts_user_id'), ['user_id'], unique=True)

    if 'moneybox_ledger' not in tables:
        op.create_table(
            'moneybox_ledger',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('account_id', sa.Integer(), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('entry_type', sa.String(length=24), nullable=False),
            sa.Column('amount', sa.Float(), nullable=False),
            sa.Column('balance_after', sa.Float(), nullable=False),
            sa.Column('reference', sa.String(length=80), nullable=True),
            sa.Column('meta', sa.Text(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['account_id'], ['moneybox_accounts.id'], ),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
            sa.PrimaryKeyConstraint('id')
        )
    try:
        idx_ledger = {i['name'] for i in insp.get_indexes('moneybox_ledger')}
    except Exception:
        idx_ledger = set()
    if 'ix_moneybox_ledger_account_id' not in idx_ledger:
        with op.batch_alter_table('moneybox_ledger', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_moneybox_ledger_account_id'), ['account_id'], unique=False)
    if 'ix_moneybox_ledger_user_id' not in idx_ledger:
        with op.batch_alter_table('moneybox_ledger', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_moneybox_ledger_user_id'), ['user_id'], unique=False)
    if 'ix_moneybox_ledger_reference' not in idx_ledger:
        with op.batch_alter_table('moneybox_ledger', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_moneybox_ledger_reference'), ['reference'], unique=False)


def downgrade():
    with op.batch_alter_table('moneybox_ledger', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_moneybox_ledger_reference'))
        batch_op.drop_index(batch_op.f('ix_moneybox_ledger_user_id'))
        batch_op.drop_index(batch_op.f('ix_moneybox_ledger_account_id'))

    op.drop_table('moneybox_ledger')

    with op.batch_alter_table('moneybox_accounts', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_moneybox_accounts_user_id'))

    op.drop_table('moneybox_accounts')
