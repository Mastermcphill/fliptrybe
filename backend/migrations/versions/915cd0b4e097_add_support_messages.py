"""add support messages

Revision ID: 915cd0b4e097
Revises: b1c2d3e4f5a6
Create Date: 2026-02-08 11:49:49.327863

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '915cd0b4e097'
down_revision = 'b1c2d3e4f5a6'
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = insp.get_table_names()
    if 'support_messages' not in tables:
        op.create_table(
            'support_messages',
            sa.Column('id', sa.Integer(), primary_key=True),
            sa.Column('user_id', sa.Integer(), nullable=False, index=True),
            sa.Column('sender_role', sa.String(length=16), nullable=False),
            sa.Column('sender_id', sa.Integer(), nullable=False),
            sa.Column('body', sa.Text(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
        )
    # indexes
    try:
        idx = {i['name'] for i in insp.get_indexes('support_messages')}
    except Exception:
        idx = set()
    if 'ix_support_messages_user_id' not in idx:
        op.create_index('ix_support_messages_user_id', 'support_messages', ['user_id'])
    if 'ix_support_messages_created_at' not in idx:
        op.create_index('ix_support_messages_created_at', 'support_messages', ['created_at'])


def downgrade():
    op.drop_index('ix_support_messages_created_at', table_name='support_messages')
    op.drop_index('ix_support_messages_user_id', table_name='support_messages')
    op.drop_table('support_messages')
