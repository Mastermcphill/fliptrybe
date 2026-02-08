"""add availability confirmations and listing lock

Revision ID: f2a3b4c5d6e7
Revises: f1a9c8d3e2b7
Create Date: 2026-02-05 14:10:00.000000
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'f2a3b4c5d6e7'
down_revision = 'f1a9c8d3e2b7'
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    existing_tables = set(insp.get_table_names())

    def _col_exists(table: str, col: str) -> bool:
        try:
            cols = [c["name"] for c in insp.get_columns(table)]
            return col in cols
        except Exception:
            return False

    def _index_exists(table: str, idx_name: str) -> bool:
        try:
            idxs = [i.get("name") for i in sa.inspect(bind).get_indexes(table)]
            return idx_name in idxs
        except Exception:
            return False

    if "availability_confirmations" not in existing_tables:
        op.create_table(
            'availability_confirmations',
            sa.Column('id', sa.Integer(), primary_key=True),
            sa.Column('order_id', sa.Integer(), sa.ForeignKey('orders.id'), nullable=False),
            sa.Column('listing_id', sa.Integer(), sa.ForeignKey('listings.id'), nullable=True),
            sa.Column('merchant_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
            sa.Column('seller_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
            sa.Column('status', sa.String(length=16), nullable=False, server_default='pending'),
            sa.Column('requested_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.Column('deadline_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.Column('responded_at', sa.DateTime(), nullable=True),
            sa.Column('response_token', sa.String(length=96), nullable=False),
            sa.UniqueConstraint('order_id', name='uq_availability_confirmations_order'),
            sa.UniqueConstraint('response_token', name='uq_availability_confirmations_token'),
        )
    if "availability_confirmations" in sa.inspect(bind).get_table_names():
        if not _index_exists('availability_confirmations', 'ix_availability_confirmations_order_id'):
            op.create_index('ix_availability_confirmations_order_id', 'availability_confirmations', ['order_id'])
        if not _index_exists('availability_confirmations', 'ix_availability_confirmations_listing_id'):
            op.create_index('ix_availability_confirmations_listing_id', 'availability_confirmations', ['listing_id'])
        if not _index_exists('availability_confirmations', 'ix_availability_confirmations_merchant_id'):
            op.create_index('ix_availability_confirmations_merchant_id', 'availability_confirmations', ['merchant_id'])
        if not _index_exists('availability_confirmations', 'ix_availability_confirmations_seller_id'):
            op.create_index('ix_availability_confirmations_seller_id', 'availability_confirmations', ['seller_id'])

    if _col_exists("listings", "is_active") is False:
        default_active = sa.text('1') if bind.dialect.name == "sqlite" else sa.text('true')
        with op.batch_alter_table('listings') as batch_op:
            batch_op.add_column(sa.Column('is_active', sa.Boolean(), nullable=False, server_default=default_active))

    if _col_exists("orders", "fulfillment_mode") is False:
        with op.batch_alter_table('orders') as batch_op:
            batch_op.add_column(sa.Column('fulfillment_mode', sa.String(length=16), nullable=False, server_default='unselected'))


def downgrade():
    with op.batch_alter_table('orders') as batch_op:
        batch_op.drop_column('fulfillment_mode')

    with op.batch_alter_table('listings') as batch_op:
        batch_op.drop_column('is_active')

    op.drop_index('ix_availability_confirmations_seller_id', table_name='availability_confirmations')
    op.drop_index('ix_availability_confirmations_merchant_id', table_name='availability_confirmations')
    op.drop_index('ix_availability_confirmations_listing_id', table_name='availability_confirmations')
    op.drop_index('ix_availability_confirmations_order_id', table_name='availability_confirmations')
    op.drop_table('availability_confirmations')
