"""orders/listings defaults and total_price parity

Revision ID: fb2c3d4e5f60
Revises: fa1b2c3d4e5f
Create Date: 2026-02-10 13:00:00.000000
"""

from __future__ import annotations

import re

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "fb2c3d4e5f60"
down_revision = "fa1b2c3d4e5f"
branch_labels = None
depends_on = None


_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _table_exists(bind, table_name: str) -> bool:
    try:
        return sa.inspect(bind).has_table(table_name)
    except Exception:
        return False


def _column_exists(bind, table_name: str, column_name: str) -> bool:
    try:
        cols = sa.inspect(bind).get_columns(table_name)
        return any(c.get("name") == column_name for c in cols)
    except Exception:
        return False


def _safe_ident(name: str) -> bool:
    return bool(name and _IDENT_RE.match(name))


def _ensure_total_price_column(bind) -> None:
    if not _table_exists(bind, "orders"):
        return

    if not _column_exists(bind, "orders", "total_price"):
        with op.batch_alter_table("orders") as batch_op:
            batch_op.add_column(sa.Column("total_price", sa.Float(), nullable=True))

    if not _column_exists(bind, "orders", "total_price"):
        return

    try:
        op.execute("UPDATE orders SET total_price = COALESCE(total_price, amount, 0) WHERE total_price IS NULL")
    except Exception:
        pass

    if bind.dialect.name != "postgresql":
        return

    try:
        op.execute("ALTER TABLE orders ALTER COLUMN total_price SET DEFAULT 0")
    except Exception:
        pass

    try:
        null_count = bind.execute(sa.text("SELECT COUNT(*) FROM orders WHERE total_price IS NULL")).scalar() or 0
        if int(null_count) == 0:
            op.execute("ALTER TABLE orders ALTER COLUMN total_price SET NOT NULL")
    except Exception:
        pass


def _default_sql_for_column(table_name: str, column_name: str, data_type: str, udt_name: str) -> str | None:
    overrides = {
        ("orders", "status"): "'created'",
        ("orders", "fulfillment_mode"): "'unselected'",
        ("orders", "escrow_status"): "'NONE'",
        ("orders", "escrow_currency"): "'NGN'",
        ("orders", "release_condition"): "'INSPECTION_PASS'",
        ("orders", "inspection_status"): "'NONE'",
        ("orders", "inspection_outcome"): "'NONE'",
        ("listings", "category"): "'declutter'",
        ("listings", "is_active"): "true",
    }
    if (table_name, column_name) in overrides:
        return overrides[(table_name, column_name)]

    if column_name == "id" or column_name.endswith("_id"):
        return None

    if udt_name == "uuid":
        return "gen_random_uuid()"

    dtype = (data_type or "").lower()
    if dtype in ("character varying", "character", "text"):
        return "''"
    if dtype in ("integer", "bigint", "smallint", "numeric", "double precision", "real"):
        return "0"
    if dtype == "boolean":
        return "false"
    if dtype.startswith("timestamp") or dtype == "date":
        return "now()"
    return None


def _set_missing_defaults_postgres(bind) -> None:
    if bind.dialect.name != "postgresql":
        return

    try:
        op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")
    except Exception:
        pass

    rows = bind.execute(
        sa.text(
            """
            SELECT table_name, column_name, data_type, udt_name
            FROM information_schema.columns
            WHERE table_schema = current_schema()
              AND table_name IN ('orders', 'listings')
              AND is_nullable = 'NO'
              AND column_default IS NULL
            ORDER BY table_name, column_name
            """
        )
    ).mappings().all()

    for row in rows:
        table_name = str(row.get("table_name") or "")
        column_name = str(row.get("column_name") or "")
        if not (_safe_ident(table_name) and _safe_ident(column_name)):
            continue
        default_sql = _default_sql_for_column(
            table_name=table_name,
            column_name=column_name,
            data_type=str(row.get("data_type") or ""),
            udt_name=str(row.get("udt_name") or ""),
        )
        if not default_sql:
            continue
        try:
            op.execute(f'ALTER TABLE "{table_name}" ALTER COLUMN "{column_name}" SET DEFAULT {default_sql}')
        except Exception:
            # Best effort: continue patching other columns.
            pass


def upgrade():
    bind = op.get_bind()
    _ensure_total_price_column(bind)
    _set_missing_defaults_postgres(bind)


def downgrade():
    # Drift repair migration is intentionally non-destructive.
    pass
