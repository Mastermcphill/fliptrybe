"""payments mode and follow hardening

Revision ID: ff6a7b8c9d01
Revises: fe5f6a7b8c90
Create Date: 2026-02-12 22:10:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "ff6a7b8c9d01"
down_revision = "fe5f6a7b8c90"
branch_labels = None
depends_on = None


def _table_exists(bind, table_name: str) -> bool:
    try:
        return sa.inspect(bind).has_table(table_name)
    except Exception:
        return False


def _column_exists(bind, table_name: str, column_name: str) -> bool:
    try:
        cols = sa.inspect(bind).get_columns(table_name)
        return any((c.get("name") or "") == column_name for c in cols)
    except Exception:
        return False


def _index_exists(bind, table_name: str, index_name: str) -> bool:
    try:
        indexes = sa.inspect(bind).get_indexes(table_name)
        return any((idx.get("name") or "") == index_name for idx in indexes)
    except Exception:
        return False


def _add_autopilot_columns(bind) -> None:
    if not _table_exists(bind, "autopilot_settings"):
        return

    to_add = []
    if not _column_exists(bind, "autopilot_settings", "payments_mode"):
        to_add.append(sa.Column("payments_mode", sa.String(length=32), nullable=False, server_default="mock"))
    if not _column_exists(bind, "autopilot_settings", "last_paystack_webhook_at"):
        to_add.append(sa.Column("last_paystack_webhook_at", sa.DateTime(), nullable=True))
    if not _column_exists(bind, "autopilot_settings", "payments_mode_changed_at"):
        to_add.append(sa.Column("payments_mode_changed_at", sa.DateTime(), nullable=True))
    if not _column_exists(bind, "autopilot_settings", "payments_mode_changed_by"):
        to_add.append(sa.Column("payments_mode_changed_by", sa.Integer(), nullable=True))

    if to_add:
        with op.batch_alter_table("autopilot_settings") as batch_op:
            for col in to_add:
                batch_op.add_column(col)

    try:
        op.execute("UPDATE autopilot_settings SET payments_mode='mock' WHERE payments_mode IS NULL")
    except Exception:
        pass


def _add_follow_columns_and_constraints(bind) -> None:
    if not _table_exists(bind, "merchant_follows"):
        return

    if not _column_exists(bind, "merchant_follows", "created_at"):
        with op.batch_alter_table("merchant_follows") as batch_op:
            batch_op.add_column(
                sa.Column("created_at", sa.DateTime(), nullable=True, server_default=sa.text("CURRENT_TIMESTAMP"))
            )
    try:
        op.execute("UPDATE merchant_follows SET created_at=CURRENT_TIMESTAMP WHERE created_at IS NULL")
    except Exception:
        pass

    dialect = bind.dialect.name
    try:
        if dialect == "postgresql":
            op.execute(
                """
                DELETE FROM merchant_follows a
                USING merchant_follows b
                WHERE a.id < b.id
                  AND a.follower_id = b.follower_id
                  AND a.merchant_id = b.merchant_id
                """
            )
        else:
            op.execute(
                """
                DELETE FROM merchant_follows
                WHERE id IN (
                    SELECT a.id
                    FROM merchant_follows a
                    JOIN merchant_follows b
                      ON a.follower_id = b.follower_id
                     AND a.merchant_id = b.merchant_id
                     AND a.id < b.id
                )
                """
            )
    except Exception:
        pass

    index_name = "uq_merchant_follows_follower_merchant"
    if not _index_exists(bind, "merchant_follows", index_name):
        if dialect == "postgresql":
            op.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS uq_merchant_follows_follower_merchant ON merchant_follows (follower_id, merchant_id)"
            )
        else:
            op.create_index(
                index_name,
                "merchant_follows",
                ["follower_id", "merchant_id"],
                unique=True,
            )


def upgrade():
    bind = op.get_bind()
    _add_autopilot_columns(bind)
    _add_follow_columns_and_constraints(bind)


def downgrade():
    # Keep downgrade non-destructive for drift-safe environments.
    pass
