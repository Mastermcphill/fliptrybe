"""commission snapshots and theme settings

Revision ID: e0f1a2b3c4d5
Revises: d9e8f7a6b5c4
Create Date: 2026-02-14 18:10:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "e0f1a2b3c4d5"
down_revision = "d9e8f7a6b5c4"
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


def _ensure_orders_columns(bind) -> None:
    if not _table_exists(bind, "orders"):
        return
    with op.batch_alter_table("orders") as batch:
        if not _column_exists(bind, "orders", "commission_snapshot_version"):
            batch.add_column(sa.Column("commission_snapshot_version", sa.Integer(), nullable=False, server_default="1"))
        if not _column_exists(bind, "orders", "commission_snapshot_json"):
            batch.add_column(sa.Column("commission_snapshot_json", sa.Text(), nullable=True))
        if not _column_exists(bind, "orders", "sale_fee_minor"):
            batch.add_column(sa.Column("sale_fee_minor", sa.Integer(), nullable=False, server_default="0"))
        if not _column_exists(bind, "orders", "sale_platform_minor"):
            batch.add_column(sa.Column("sale_platform_minor", sa.Integer(), nullable=False, server_default="0"))
        if not _column_exists(bind, "orders", "sale_seller_minor"):
            batch.add_column(sa.Column("sale_seller_minor", sa.Integer(), nullable=False, server_default="0"))
        if not _column_exists(bind, "orders", "sale_top_tier_incentive_minor"):
            batch.add_column(sa.Column("sale_top_tier_incentive_minor", sa.Integer(), nullable=False, server_default="0"))
        if not _column_exists(bind, "orders", "delivery_actor_minor"):
            batch.add_column(sa.Column("delivery_actor_minor", sa.Integer(), nullable=False, server_default="0"))
        if not _column_exists(bind, "orders", "delivery_platform_minor"):
            batch.add_column(sa.Column("delivery_platform_minor", sa.Integer(), nullable=False, server_default="0"))
        if not _column_exists(bind, "orders", "inspection_actor_minor"):
            batch.add_column(sa.Column("inspection_actor_minor", sa.Integer(), nullable=False, server_default="0"))
        if not _column_exists(bind, "orders", "inspection_platform_minor"):
            batch.add_column(sa.Column("inspection_platform_minor", sa.Integer(), nullable=False, server_default="0"))


def _ensure_user_settings_columns(bind) -> None:
    if not _table_exists(bind, "user_settings"):
        return
    with op.batch_alter_table("user_settings") as batch:
        if not _column_exists(bind, "user_settings", "theme_mode"):
            batch.add_column(sa.Column("theme_mode", sa.String(length=16), nullable=False, server_default="system"))
        if not _column_exists(bind, "user_settings", "background_palette"):
            batch.add_column(sa.Column("background_palette", sa.String(length=24), nullable=False, server_default="neutral"))


def upgrade():
    bind = op.get_bind()
    _ensure_orders_columns(bind)
    _ensure_user_settings_columns(bind)

    if _table_exists(bind, "user_settings"):
        op.execute(sa.text("UPDATE user_settings SET theme_mode='system' WHERE theme_mode IS NULL OR TRIM(theme_mode)=''"))
        op.execute(sa.text("UPDATE user_settings SET background_palette='neutral' WHERE background_palette IS NULL OR TRIM(background_palette)=''"))


def downgrade():
    bind = op.get_bind()
    if _table_exists(bind, "user_settings"):
        with op.batch_alter_table("user_settings") as batch:
            if _column_exists(bind, "user_settings", "background_palette"):
                batch.drop_column("background_palette")
            if _column_exists(bind, "user_settings", "theme_mode"):
                batch.drop_column("theme_mode")
    if _table_exists(bind, "orders"):
        with op.batch_alter_table("orders") as batch:
            if _column_exists(bind, "orders", "inspection_platform_minor"):
                batch.drop_column("inspection_platform_minor")
            if _column_exists(bind, "orders", "inspection_actor_minor"):
                batch.drop_column("inspection_actor_minor")
            if _column_exists(bind, "orders", "delivery_platform_minor"):
                batch.drop_column("delivery_platform_minor")
            if _column_exists(bind, "orders", "delivery_actor_minor"):
                batch.drop_column("delivery_actor_minor")
            if _column_exists(bind, "orders", "sale_top_tier_incentive_minor"):
                batch.drop_column("sale_top_tier_incentive_minor")
            if _column_exists(bind, "orders", "sale_seller_minor"):
                batch.drop_column("sale_seller_minor")
            if _column_exists(bind, "orders", "sale_platform_minor"):
                batch.drop_column("sale_platform_minor")
            if _column_exists(bind, "orders", "sale_fee_minor"):
                batch.drop_column("sale_fee_minor")
            if _column_exists(bind, "orders", "commission_snapshot_json"):
                batch.drop_column("commission_snapshot_json")
            if _column_exists(bind, "orders", "commission_snapshot_version"):
                batch.drop_column("commission_snapshot_version")
