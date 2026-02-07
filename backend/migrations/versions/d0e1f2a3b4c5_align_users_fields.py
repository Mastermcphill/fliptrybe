from alembic import op
import sqlalchemy as sa

revision = 'd0e1f2a3b4c5'
down_revision = 'c9f7b2a6d1e0'
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

    dialect = bind.dialect.name
    created_default = sa.text('CURRENT_TIMESTAMP') if dialect == 'sqlite' else sa.text('now()')

    with op.batch_alter_table('users') as batch_op:
        if not _has_column(inspector, 'users', 'created_at'):
            batch_op.add_column(
                sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=created_default)
            )
        if not _has_column(inspector, 'users', 'role'):
            batch_op.add_column(
                sa.Column('role', sa.String(length=50), nullable=False, server_default='buyer')
            )
        if not _has_column(inspector, 'users', 'kyc_tier'):
            batch_op.add_column(
                sa.Column('kyc_tier', sa.Integer(), nullable=False, server_default='0')
            )
        if not _has_column(inspector, 'users', 'is_available'):
            batch_op.add_column(
                sa.Column('is_available', sa.Boolean(), nullable=False, server_default=sa.text('1') if dialect == 'sqlite' else sa.true())
            )

    # Backfill role if legacy flags exist
    has_is_admin = _has_column(inspector, 'users', 'is_admin')
    has_is_driver = _has_column(inspector, 'users', 'is_driver')
    if has_is_admin or has_is_driver:
        if dialect == 'sqlite':
            if has_is_admin:
                op.execute("UPDATE users SET role='admin' WHERE is_admin=1")
            if has_is_driver:
                op.execute("UPDATE users SET role='driver' WHERE is_driver=1 AND (role IS NULL OR role='buyer')")
        else:
            if has_is_admin:
                op.execute("UPDATE users SET role='admin' WHERE is_admin = true")
            if has_is_driver:
                op.execute("UPDATE users SET role='driver' WHERE is_driver = true AND (role IS NULL OR role='buyer')")


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not _has_table(inspector, 'users'):
        return

    with op.batch_alter_table('users') as batch_op:
        if _has_column(inspector, 'users', 'is_available'):
            batch_op.drop_column('is_available')
        if _has_column(inspector, 'users', 'kyc_tier'):
            batch_op.drop_column('kyc_tier')
        if _has_column(inspector, 'users', 'role'):
            batch_op.drop_column('role')
        if _has_column(inspector, 'users', 'created_at'):
            batch_op.drop_column('created_at')
