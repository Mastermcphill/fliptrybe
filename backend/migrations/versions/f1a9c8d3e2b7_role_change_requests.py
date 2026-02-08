"""role change requests

Revision ID: f1a9c8d3e2b7
Revises: e2c3d7f4a1b9
Create Date: 2026-02-04 12:05:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'f1a9c8d3e2b7'
down_revision = 'e2c3d7f4a1b9'
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())
    if 'role_change_requests' not in tables:
        op.create_table(
            'role_change_requests',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('current_role', sa.String(length=32), nullable=False),
            sa.Column('requested_role', sa.String(length=32), nullable=False),
            sa.Column('reason', sa.String(length=400), nullable=True),
            sa.Column('status', sa.String(length=16), nullable=False),
            sa.Column('admin_user_id', sa.Integer(), nullable=True),
            sa.Column('decided_at', sa.DateTime(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['admin_user_id'], ['users.id'], ),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
            sa.PrimaryKeyConstraint('id')
        )
    try:
        idx = {i['name'] for i in insp.get_indexes('role_change_requests')}
    except Exception:
        idx = set()
    if 'ix_role_change_requests_user_id' not in idx:
        with op.batch_alter_table('role_change_requests', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_role_change_requests_user_id'), ['user_id'], unique=False)


def downgrade():
    with op.batch_alter_table('role_change_requests', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_role_change_requests_user_id'))

    op.drop_table('role_change_requests')
