"""add escrow unlocks, qr challenges, inspection tickets

Revision ID: a3b4c5d6e7f8
Revises: f2a3b4c5d6e7
Create Date: 2026-02-06 10:00:00.000000
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a3b4c5d6e7f8'
down_revision = 'f2a3b4c5d6e7'
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    existing_tables = set(insp.get_table_names())

    def _index_exists(table_name: str, index_name: str) -> bool:
        try:
            idxs = [i.get("name") for i in sa.inspect(bind).get_indexes(table_name)]
            return index_name in idxs
        except Exception:
            return False

    if "escrow_unlocks" not in existing_tables:
        op.create_table(
            'escrow_unlocks',
            sa.Column('id', sa.Integer(), primary_key=True),
            sa.Column('order_id', sa.Integer(), sa.ForeignKey('orders.id'), nullable=False),
            sa.Column('step', sa.String(length=32), nullable=False),
            sa.Column('code_hash', sa.String(length=128), nullable=True),
            sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('max_attempts', sa.Integer(), nullable=False, server_default='4'),
            sa.Column('locked', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('qr_required', sa.Boolean(), nullable=False, server_default=sa.text('1')),
            sa.Column('qr_verified', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('qr_verified_at', sa.DateTime(), nullable=True),
            sa.Column('unlocked_at', sa.DateTime(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.Column('expires_at', sa.DateTime(), nullable=True),
            sa.Column('admin_unlock_token_hash', sa.String(length=128), nullable=True),
            sa.Column('admin_unlock_expires_at', sa.DateTime(), nullable=True),
            sa.UniqueConstraint('order_id', 'step', name='uq_escrow_unlock_order_step'),
        )
    if "escrow_unlocks" in sa.inspect(bind).get_table_names():
        if not _index_exists('escrow_unlocks', 'ix_escrow_unlocks_order_id'):
            op.create_index('ix_escrow_unlocks_order_id', 'escrow_unlocks', ['order_id'])
        if not _index_exists('escrow_unlocks', 'ix_escrow_unlocks_step'):
            op.create_index('ix_escrow_unlocks_step', 'escrow_unlocks', ['step'])

    if "qr_challenges" not in existing_tables:
        op.create_table(
            'qr_challenges',
            sa.Column('id', sa.Integer(), primary_key=True),
            sa.Column('order_id', sa.Integer(), sa.ForeignKey('orders.id'), nullable=False),
            sa.Column('step', sa.String(length=32), nullable=False),
            sa.Column('issued_to_role', sa.String(length=16), nullable=False),
            sa.Column('challenge_hash', sa.String(length=128), nullable=False),
            sa.Column('status', sa.String(length=16), nullable=False, server_default='issued'),
            sa.Column('scanned_by_user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
            sa.Column('issued_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.Column('scanned_at', sa.DateTime(), nullable=True),
            sa.Column('expires_at', sa.DateTime(), nullable=True),
            sa.UniqueConstraint('challenge_hash', name='uq_qr_challenge_hash'),
        )
    if "qr_challenges" in sa.inspect(bind).get_table_names():
        if not _index_exists('qr_challenges', 'ix_qr_challenges_order_id'):
            op.create_index('ix_qr_challenges_order_id', 'qr_challenges', ['order_id'])
        if not _index_exists('qr_challenges', 'ix_qr_challenges_step'):
            op.create_index('ix_qr_challenges_step', 'qr_challenges', ['step'])
        if not _index_exists('qr_challenges', 'ix_qr_challenges_scanned_by_user_id'):
            op.create_index('ix_qr_challenges_scanned_by_user_id', 'qr_challenges', ['scanned_by_user_id'])

    if "inspection_tickets" not in existing_tables:
        op.create_table(
            'inspection_tickets',
            sa.Column('id', sa.Integer(), primary_key=True),
            sa.Column('order_id', sa.Integer(), sa.ForeignKey('orders.id'), nullable=False),
            sa.Column('inspector_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
            sa.Column('seller_phone', sa.String(length=32), nullable=True),
            sa.Column('seller_address', sa.String(length=200), nullable=True),
            sa.Column('item_summary', sa.String(length=200), nullable=True),
            sa.Column('buyer_full_name', sa.String(length=120), nullable=True),
            sa.Column('buyer_phone', sa.String(length=32), nullable=True),
            sa.Column('scheduled_for', sa.DateTime(), nullable=True),
            sa.Column('status', sa.String(length=16), nullable=False, server_default='created'),
            sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.UniqueConstraint('order_id', name='uq_inspection_ticket_order'),
        )
    if "inspection_tickets" in sa.inspect(bind).get_table_names():
        if not _index_exists('inspection_tickets', 'ix_inspection_tickets_order_id'):
            op.create_index('ix_inspection_tickets_order_id', 'inspection_tickets', ['order_id'])
        if not _index_exists('inspection_tickets', 'ix_inspection_tickets_inspector_id'):
            op.create_index('ix_inspection_tickets_inspector_id', 'inspection_tickets', ['inspector_id'])


def downgrade():
    op.drop_index('ix_inspection_tickets_inspector_id', table_name='inspection_tickets')
    op.drop_index('ix_inspection_tickets_order_id', table_name='inspection_tickets')
    op.drop_table('inspection_tickets')

    op.drop_index('ix_qr_challenges_scanned_by_user_id', table_name='qr_challenges')
    op.drop_index('ix_qr_challenges_step', table_name='qr_challenges')
    op.drop_index('ix_qr_challenges_order_id', table_name='qr_challenges')
    op.drop_table('qr_challenges')

    op.drop_index('ix_escrow_unlocks_step', table_name='escrow_unlocks')
    op.drop_index('ix_escrow_unlocks_order_id', table_name='escrow_unlocks')
    op.drop_table('escrow_unlocks')
