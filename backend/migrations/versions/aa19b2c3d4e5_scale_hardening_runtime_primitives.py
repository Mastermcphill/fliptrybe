"""scale hardening runtime primitives

Revision ID: aa19b2c3d4e5
Revises: 2f3a4b5c6d7e
Create Date: 2026-02-19 18:30:00.000000

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect, text


# revision identifiers, used by Alembic.
revision = "aa19b2c3d4e5"
down_revision = "2f3a4b5c6d7e"
branch_labels = None
depends_on = None


def _table_exists(insp, table_name: str) -> bool:
    try:
        return table_name in set(insp.get_table_names())
    except Exception:
        return False


def _column_names(insp, table_name: str) -> set[str]:
    try:
        return {str(c.get("name") or "") for c in insp.get_columns(table_name)}
    except Exception:
        return set()


def _index_exists(insp, table_name: str, index_name: str) -> bool:
    try:
        indexes = insp.get_indexes(table_name) or []
        return any(str(idx.get("name") or "") == str(index_name) for idx in indexes)
    except Exception:
        return False


def _unique_exists(insp, table_name: str, unique_name: str) -> bool:
    try:
        uniques = insp.get_unique_constraints(table_name) or []
        return any(str(row.get("name") or "") == str(unique_name) for row in uniques)
    except Exception:
        return False


def _create_index_if_possible(insp, table_name: str, index_name: str, columns: list[str], *, unique: bool = False):
    if _index_exists(insp, table_name, index_name):
        return
    existing_columns = _column_names(insp, table_name)
    if not all(col in existing_columns for col in columns):
        return
    op.create_index(index_name, table_name, columns, unique=unique)


def upgrade():
    bind = op.get_bind()
    insp = inspect(bind)

    if _table_exists(insp, "idempotency_keys"):
        cols_before = _column_names(insp, "idempotency_keys")
        with op.batch_alter_table("idempotency_keys", schema=None) as batch_op:
            if "scope" not in cols_before:
                batch_op.add_column(sa.Column("scope", sa.String(length=128), nullable=False, server_default=""))
            if "response_body_json" not in cols_before:
                batch_op.add_column(sa.Column("response_body_json", sa.Text(), nullable=True))
            if "response_code" not in cols_before:
                batch_op.add_column(sa.Column("response_code", sa.Integer(), nullable=False, server_default="200"))
            if "updated_at" not in cols_before:
                batch_op.add_column(sa.Column("updated_at", sa.DateTime(), nullable=True))
        try:
            bind.execute(
                text(
                    "UPDATE idempotency_keys SET scope = COALESCE(NULLIF(scope, ''), route, '')"
                )
            )
        except Exception:
            pass
        try:
            bind.execute(
                text(
                    "UPDATE idempotency_keys SET response_code = COALESCE(response_code, status_code, 200)"
                )
            )
        except Exception:
            pass
        try:
            bind.execute(
                text(
                    "UPDATE idempotency_keys SET response_body_json = COALESCE(response_body_json, response_json)"
                )
            )
        except Exception:
            pass
        try:
            bind.execute(
                text(
                    "UPDATE idempotency_keys SET updated_at = COALESCE(updated_at, created_at, CURRENT_TIMESTAMP)"
                )
            )
        except Exception:
            pass

        insp = inspect(bind)
        if not _unique_exists(insp, "idempotency_keys", "uq_idempotency_scope_key"):
            try:
                with op.batch_alter_table("idempotency_keys", schema=None) as batch_op:
                    batch_op.create_unique_constraint("uq_idempotency_scope_key", ["scope", "key"])
            except Exception:
                # Fallback for engines where unique constraints are represented as unique indexes.
                if not _index_exists(insp, "idempotency_keys", "uq_idempotency_scope_key"):
                    op.create_index("uq_idempotency_scope_key", "idempotency_keys", ["scope", "key"], unique=True)
        _create_index_if_possible(insp, "idempotency_keys", "ix_idempotency_keys_scope", ["scope"])
        _create_index_if_possible(insp, "idempotency_keys", "ix_idempotency_keys_key", ["key"])

    insp = inspect(bind)
    if _table_exists(insp, "listings"):
        _create_index_if_possible(
            insp,
            "listings",
            "ix_listings_hot_read_path",
            ["state", "city", "category_id", "is_active", "approval_status"],
        )

    insp = inspect(bind)
    if _table_exists(insp, "orders"):
        _create_index_if_possible(
            insp,
            "orders",
            "ix_orders_buyer_created_at",
            ["buyer_id", "created_at"],
        )
        _create_index_if_possible(
            insp,
            "orders",
            "ix_orders_listing_id_hot",
            ["listing_id"],
        )

    insp = inspect(bind)
    if _table_exists(insp, "wallet_txns"):
        _create_index_if_possible(
            insp,
            "wallet_txns",
            "ix_wallet_txns_wallet_created_at",
            ["wallet_id", "created_at"],
        )


def downgrade():
    bind = op.get_bind()
    insp = inspect(bind)
    if _table_exists(insp, "wallet_txns") and _index_exists(insp, "wallet_txns", "ix_wallet_txns_wallet_created_at"):
        op.drop_index("ix_wallet_txns_wallet_created_at", table_name="wallet_txns")
    if _table_exists(insp, "orders") and _index_exists(insp, "orders", "ix_orders_listing_id_hot"):
        op.drop_index("ix_orders_listing_id_hot", table_name="orders")
    if _table_exists(insp, "orders") and _index_exists(insp, "orders", "ix_orders_buyer_created_at"):
        op.drop_index("ix_orders_buyer_created_at", table_name="orders")
    if _table_exists(insp, "listings") and _index_exists(insp, "listings", "ix_listings_hot_read_path"):
        op.drop_index("ix_listings_hot_read_path", table_name="listings")
    if _table_exists(insp, "idempotency_keys"):
        with op.batch_alter_table("idempotency_keys", schema=None) as batch_op:
            try:
                batch_op.drop_constraint("uq_idempotency_scope_key", type_="unique")
            except Exception:
                pass
        insp = inspect(bind)
        if _index_exists(insp, "idempotency_keys", "uq_idempotency_scope_key"):
            op.drop_index("uq_idempotency_scope_key", table_name="idempotency_keys")
        if _index_exists(insp, "idempotency_keys", "ix_idempotency_keys_scope"):
            op.drop_index("ix_idempotency_keys_scope", table_name="idempotency_keys")
        with op.batch_alter_table("idempotency_keys", schema=None) as batch_op:
            cols = _column_names(inspect(bind), "idempotency_keys")
            if "updated_at" in cols:
                batch_op.drop_column("updated_at")
            if "response_code" in cols:
                batch_op.drop_column("response_code")
            if "response_body_json" in cols:
                batch_op.drop_column("response_body_json")
            if "scope" in cols:
                batch_op.drop_column("scope")
