"""add inspector requests

Revision ID: d2f3e4a5b6c7
Revises: 915cd0b4e097
Create Date: 2026-02-09 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'd2f3e4a5b6c7'
down_revision = '915cd0b4e097'
branch_labels = None
depends_on = None


def _table_exists(bind, name: str) -> bool:
    try:
        insp = sa.inspect(bind)
        return insp.has_table(name)
    except Exception:
        return False


def upgrade():
    bind = op.get_bind()
    if _table_exists(bind, 'inspector_requests'):
        return

    op.create_table(
        'inspector_requests',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('name', sa.String(length=200), nullable=False),
        sa.Column('email', sa.String(length=200), nullable=False),
        sa.Column('phone', sa.String(length=50), nullable=False),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('status', sa.String(length=40), nullable=False, server_default='pending'),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('decided_at', sa.DateTime(), nullable=True),
        sa.Column('decided_by', sa.Integer(), nullable=True),
    )
    op.create_index('ix_inspector_requests_email', 'inspector_requests', ['email'])
    op.create_index('ix_inspector_requests_phone', 'inspector_requests', ['phone'])
    op.create_index('ix_inspector_requests_status', 'inspector_requests', ['status'])


def downgrade():
    bind = op.get_bind()
    if not _table_exists(bind, 'inspector_requests'):
        return
    op.drop_index('ix_inspector_requests_status', table_name='inspector_requests')
    op.drop_index('ix_inspector_requests_phone', table_name='inspector_requests')
    op.drop_index('ix_inspector_requests_email', table_name='inspector_requests')
    op.drop_table('inspector_requests')
