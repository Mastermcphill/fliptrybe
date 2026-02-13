"""autosave and taxonomy touchup

Revision ID: d9e8f7a6b5c4
Revises: c3d4e5f6a7b8
Create Date: 2026-02-13 23:10:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "d9e8f7a6b5c4"
down_revision = "c3d4e5f6a7b8"
branch_labels = None
depends_on = None


def _table_exists(bind, table_name: str) -> bool:
    try:
        return sa.inspect(bind).has_table(table_name)
    except Exception:
        return False


def _index_exists(bind, table_name: str, index_name: str) -> bool:
    try:
        rows = sa.inspect(bind).get_indexes(table_name)
        return any((row.get("name") or "") == index_name for row in rows)
    except Exception:
        return False


def _constraint_exists(bind, table_name: str, constraint_name: str) -> bool:
    try:
        rows = sa.inspect(bind).get_check_constraints(table_name)
        return any((row.get("name") or "") == constraint_name for row in rows)
    except Exception:
        return False


def upgrade():
    bind = op.get_bind()
    dialect = (getattr(bind.dialect, "name", "") or "").lower()

    if _table_exists(bind, "moneybox_accounts"):
        op.execute(
            sa.text(
                "UPDATE moneybox_accounts "
                "SET autosave_percent = CASE "
                "WHEN autosave_percent < 0 THEN 0 "
                "WHEN autosave_percent > 30 THEN 30 "
                "ELSE autosave_percent END"
            )
        )
        if dialect == "postgresql" and not _constraint_exists(
            bind, "moneybox_accounts", "chk_moneybox_accounts_autosave_percent_range"
        ):
            op.execute(
                sa.text(
                    "ALTER TABLE moneybox_accounts "
                    "ADD CONSTRAINT chk_moneybox_accounts_autosave_percent_range "
                    "CHECK (autosave_percent >= 0 AND autosave_percent <= 30)"
                )
            )

    if _table_exists(bind, "listings") and not _index_exists(
        bind, "listings", "ix_listings_category_brand_model"
    ):
        with op.batch_alter_table("listings") as batch:
            batch.create_index(
                "ix_listings_category_brand_model",
                ["category_id", "brand_id", "model_id"],
                unique=False,
            )

    if _table_exists(bind, "categories") and not _index_exists(
        bind, "categories", "ix_categories_parent_sort"
    ):
        with op.batch_alter_table("categories") as batch:
            batch.create_index(
                "ix_categories_parent_sort",
                ["parent_id", "sort_order"],
                unique=False,
            )


def downgrade():
    bind = op.get_bind()
    if _table_exists(bind, "categories") and _index_exists(
        bind, "categories", "ix_categories_parent_sort"
    ):
        with op.batch_alter_table("categories") as batch:
            batch.drop_index("ix_categories_parent_sort")

    if _table_exists(bind, "listings") and _index_exists(
        bind, "listings", "ix_listings_category_brand_model"
    ):
        with op.batch_alter_table("listings") as batch:
            batch.drop_index("ix_listings_category_brand_model")

    if _table_exists(bind, "moneybox_accounts"):
        dialect = (getattr(bind.dialect, "name", "") or "").lower()
        if dialect == "postgresql" and _constraint_exists(
            bind, "moneybox_accounts", "chk_moneybox_accounts_autosave_percent_range"
        ):
            op.execute(
                sa.text(
                    "ALTER TABLE moneybox_accounts "
                    "DROP CONSTRAINT chk_moneybox_accounts_autosave_percent_range"
                )
            )
