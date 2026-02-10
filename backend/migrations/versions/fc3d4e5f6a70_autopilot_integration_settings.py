"""autopilot integration settings

Revision ID: fc3d4e5f6a70
Revises: fb2c3d4e5f60
Create Date: 2026-02-10 18:30:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "fc3d4e5f6a70"
down_revision = "fb2c3d4e5f60"
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


def _add_missing_columns(bind) -> None:
    if not _table_exists(bind, "autopilot_settings"):
        return

    to_add = []
    if not _column_exists(bind, "autopilot_settings", "payments_provider"):
        to_add.append(sa.Column("payments_provider", sa.String(length=24), nullable=False, server_default="mock"))
    if not _column_exists(bind, "autopilot_settings", "paystack_enabled"):
        to_add.append(sa.Column("paystack_enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists(bind, "autopilot_settings", "termii_enabled_sms"):
        to_add.append(sa.Column("termii_enabled_sms", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists(bind, "autopilot_settings", "termii_enabled_wa"):
        to_add.append(sa.Column("termii_enabled_wa", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists(bind, "autopilot_settings", "integrations_mode"):
        to_add.append(sa.Column("integrations_mode", sa.String(length=24), nullable=False, server_default="disabled"))

    if not to_add:
        return

    with op.batch_alter_table("autopilot_settings") as batch_op:
        for col in to_add:
            batch_op.add_column(col)


def upgrade():
    bind = op.get_bind()
    _add_missing_columns(bind)


def downgrade():
    # Drift-safe migration; keep non-destructive downgrade.
    pass
