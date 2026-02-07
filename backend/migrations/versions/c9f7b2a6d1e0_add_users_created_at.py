from datetime import datetime
from alembic import op
import sqlalchemy as sa

revision = 'c9f7b2a6d1e0'
down_revision = '004fb573e0dd'
branch_labels = None
depends_on = None


def _has_table(inspector, table_name: str) -> bool:
    try:
        return table_name in inspector.get_table_names()
    except Exception:
        return False


def _has_column(inspector, table_name: str, column_name: str) -> bool:
    try:
        cols = inspector.get_columns(table_name)
        return any(c.get('name') == column_name for c in cols)
    except Exception:
        return False


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not _has_table(inspector, 'users'):
        return

    if _has_column(inspector, 'users', 'created_at'):
        return

    with op.batch_alter_table('users') as batch_op:
        batch_op.add_column(
                sa.Column(
                    'created_at',
                    sa.DateTime(timezone=True),
                    nullable=False,
                    server_default=sa.text('now()')
                )
        )


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not _has_table(inspector, 'users'):
        return

    if not _has_column(inspector, 'users', 'created_at'):
        return

    with op.batch_alter_table('users') as batch_op:
        batch_op.drop_column('created_at')
