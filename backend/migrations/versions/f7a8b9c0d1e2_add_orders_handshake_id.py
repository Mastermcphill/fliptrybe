"""add orders.handshake_id

Revision ID: f7a8b9c0d1e2
Revises: d4e5f6a7b8c9
Create Date: 2026-02-09
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "f7a8b9c0d1e2"
down_revision = "d4e5f6a7b8c9"
branch_labels = None
depends_on = None


def _ensure_uuid_default_pg():
    # Prefer pgcrypto; fall back to uuid-ossp if needed.
    try:
        op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")
        op.execute("ALTER TABLE orders ALTER COLUMN handshake_id SET DEFAULT gen_random_uuid()")
        return
    except Exception:
        pass
    try:
        op.execute('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"')
        op.execute("ALTER TABLE orders ALTER COLUMN handshake_id SET DEFAULT uuid_generate_v4()")
    except Exception:
        pass


def upgrade():
    conn = op.get_bind()
    insp = inspect(conn)
    cols = {c["name"]: c for c in insp.get_columns("orders")}
    dialect = conn.dialect.name

    if "handshake_id" not in cols:
        col_type = postgresql.UUID(as_uuid=False) if dialect == "postgresql" else sa.String(64)
        op.add_column("orders", sa.Column("handshake_id", col_type, nullable=True))
        if dialect == "postgresql":
            _ensure_uuid_default_pg()
    else:
        if dialect == "postgresql":
            default = cols["handshake_id"].get("default")
            if not default:
                _ensure_uuid_default_pg()


def downgrade():
    conn = op.get_bind()
    insp = inspect(conn)
    cols = {c["name"]: c for c in insp.get_columns("orders")}
    if "handshake_id" in cols:
        with op.batch_alter_table("orders") as batch_op:
            batch_op.drop_column("handshake_id")
