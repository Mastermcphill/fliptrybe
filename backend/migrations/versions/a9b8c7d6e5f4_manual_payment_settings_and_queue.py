"""manual payment settings and queue support

Revision ID: a9b8c7d6e5f4
Revises: ff6a7b8c9d01
Create Date: 2026-02-13 02:40:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "a9b8c7d6e5f4"
down_revision = "ff6a7b8c9d01"
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


def _add_autopilot_manual_columns(bind) -> None:
    if not _table_exists(bind, "autopilot_settings"):
        return

    to_add = []
    if not _column_exists(bind, "autopilot_settings", "manual_payment_bank_name"):
        to_add.append(sa.Column("manual_payment_bank_name", sa.String(length=120), nullable=False, server_default=""))
    if not _column_exists(bind, "autopilot_settings", "manual_payment_account_number"):
        to_add.append(sa.Column("manual_payment_account_number", sa.String(length=64), nullable=False, server_default=""))
    if not _column_exists(bind, "autopilot_settings", "manual_payment_account_name"):
        to_add.append(sa.Column("manual_payment_account_name", sa.String(length=120), nullable=False, server_default=""))
    if not _column_exists(bind, "autopilot_settings", "manual_payment_note"):
        to_add.append(sa.Column("manual_payment_note", sa.String(length=240), nullable=False, server_default=""))
    if not _column_exists(bind, "autopilot_settings", "manual_payment_sla_minutes"):
        to_add.append(sa.Column("manual_payment_sla_minutes", sa.Integer(), nullable=False, server_default=sa.text("360")))

    if to_add:
        with op.batch_alter_table("autopilot_settings") as batch_op:
            for col in to_add:
                batch_op.add_column(col)

    try:
        op.execute("UPDATE autopilot_settings SET manual_payment_bank_name='' WHERE manual_payment_bank_name IS NULL")
    except Exception:
        pass
    try:
        op.execute("UPDATE autopilot_settings SET manual_payment_account_number='' WHERE manual_payment_account_number IS NULL")
    except Exception:
        pass
    try:
        op.execute("UPDATE autopilot_settings SET manual_payment_account_name='' WHERE manual_payment_account_name IS NULL")
    except Exception:
        pass
    try:
        op.execute("UPDATE autopilot_settings SET manual_payment_note='' WHERE manual_payment_note IS NULL")
    except Exception:
        pass
    try:
        op.execute("UPDATE autopilot_settings SET manual_payment_sla_minutes=360 WHERE manual_payment_sla_minutes IS NULL")
    except Exception:
        pass


def upgrade():
    bind = op.get_bind()
    _add_autopilot_manual_columns(bind)


def downgrade():
    # Keep downgrade non-destructive for drift-safe environments.
    pass

