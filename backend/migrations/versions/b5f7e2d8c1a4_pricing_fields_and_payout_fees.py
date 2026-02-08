"""pricing fields and payout fees

Revision ID: b5f7e2d8c1a4
Revises: c5c9b2855c3a
Create Date: 2026-02-04 10:20:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'b5f7e2d8c1a4'
down_revision = 'c5c9b2855c3a'
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    def _cols(table):
        try:
            return {c['name'] for c in insp.get_columns(table)}
        except Exception:
            return set()

    listing_cols = _cols('listings')
    shortlet_cols = _cols('shortlets')
    merchant_cols = _cols('merchant_profiles')
    payout_cols = _cols('payout_requests')

    with op.batch_alter_table('listings', schema=None) as batch_op:
        if 'base_price' not in listing_cols:
            batch_op.add_column(sa.Column('base_price', sa.Float(), nullable=False, server_default='0.0'))
        if 'platform_fee' not in listing_cols:
            batch_op.add_column(sa.Column('platform_fee', sa.Float(), nullable=False, server_default='0.0'))
        if 'final_price' not in listing_cols:
            batch_op.add_column(sa.Column('final_price', sa.Float(), nullable=False, server_default='0.0'))

    with op.batch_alter_table('shortlets', schema=None) as batch_op:
        if 'base_price' not in shortlet_cols:
            batch_op.add_column(sa.Column('base_price', sa.Float(), nullable=False, server_default='0.0'))
        if 'platform_fee' not in shortlet_cols:
            batch_op.add_column(sa.Column('platform_fee', sa.Float(), nullable=False, server_default='0.0'))
        if 'final_price' not in shortlet_cols:
            batch_op.add_column(sa.Column('final_price', sa.Float(), nullable=False, server_default='0.0'))

    with op.batch_alter_table('merchant_profiles', schema=None) as batch_op:
        if 'is_top_tier' not in merchant_cols:
            batch_op.add_column(sa.Column('is_top_tier', sa.Boolean(), nullable=False, server_default=sa.text('0')))

    with op.batch_alter_table('payout_requests', schema=None) as batch_op:
        if 'fee_amount' not in payout_cols:
            batch_op.add_column(sa.Column('fee_amount', sa.Float(), nullable=False, server_default='0.0'))
        if 'net_amount' not in payout_cols:
            batch_op.add_column(sa.Column('net_amount', sa.Float(), nullable=False, server_default='0.0'))
        if 'speed' not in payout_cols:
            batch_op.add_column(sa.Column('speed', sa.String(length=16), nullable=False, server_default='standard'))


def downgrade():
    with op.batch_alter_table('payout_requests', schema=None) as batch_op:
        batch_op.drop_column('speed')
        batch_op.drop_column('net_amount')
        batch_op.drop_column('fee_amount')

    with op.batch_alter_table('merchant_profiles', schema=None) as batch_op:
        batch_op.drop_column('is_top_tier')

    with op.batch_alter_table('shortlets', schema=None) as batch_op:
        batch_op.drop_column('final_price')
        batch_op.drop_column('platform_fee')
        batch_op.drop_column('base_price')

    with op.batch_alter_table('listings', schema=None) as batch_op:
        batch_op.drop_column('final_price')
        batch_op.drop_column('platform_fee')
        batch_op.drop_column('base_price')
