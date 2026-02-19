"""pricing benchmarks + commission policy engine

Revision ID: f7d8e9a0b1c2
Revises: f6b7c8d9e0f1
Create Date: 2026-02-14 22:40:00.000000
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "f7d8e9a0b1c2"
down_revision = "f6b7c8d9e0f1"
branch_labels = None
depends_on = None


def _create_index_if_missing(inspector, table_name: str, index_name: str, columns: list[str]) -> None:
    existing = {str(idx.get("name") or "") for idx in inspector.get_indexes(table_name)}
    if index_name not in existing:
        op.create_index(index_name, table_name, columns, unique=False)


def _drop_index_if_exists(inspector, table_name: str, index_name: str) -> None:
    existing = {str(idx.get("name") or "") for idx in inspector.get_indexes(table_name)}
    if index_name in existing:
        op.drop_index(index_name, table_name=table_name)


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if not inspector.has_table("pricing_benchmarks"):
        op.create_table(
            "pricing_benchmarks",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("category", sa.String(length=24), nullable=False),
            sa.Column("city", sa.String(length=64), nullable=False),
            sa.Column("item_type", sa.String(length=120), nullable=True),
            sa.Column("p25_minor", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("p50_minor", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("p75_minor", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("sample_size", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("category", "city", "item_type", name="uq_pricing_benchmark_scope"),
        )
    _create_index_if_missing(inspector, "pricing_benchmarks", "ix_pricing_benchmarks_category", ["category"])
    _create_index_if_missing(inspector, "pricing_benchmarks", "ix_pricing_benchmarks_city", ["city"])
    _create_index_if_missing(inspector, "pricing_benchmarks", "ix_pricing_benchmarks_item_type", ["item_type"])
    _create_index_if_missing(inspector, "pricing_benchmarks", "ix_pricing_benchmarks_updated_at", ["updated_at"])

    if not inspector.has_table("commission_policies"):
        op.create_table(
            "commission_policies",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("name", sa.String(length=120), nullable=False),
            sa.Column("status", sa.String(length=16), nullable=False, server_default="draft"),
            sa.Column("created_by_admin_id", sa.Integer(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("activated_at", sa.DateTime(), nullable=True),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.ForeignKeyConstraint(["created_by_admin_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
        )
    _create_index_if_missing(inspector, "commission_policies", "ix_commission_policies_status", ["status"])
    _create_index_if_missing(inspector, "commission_policies", "ix_commission_policies_created_by_admin_id", ["created_by_admin_id"])
    _create_index_if_missing(inspector, "commission_policies", "ix_commission_policies_created_at", ["created_at"])
    _create_index_if_missing(inspector, "commission_policies", "ix_commission_policies_activated_at", ["activated_at"])

    if not inspector.has_table("commission_policy_rules"):
        op.create_table(
            "commission_policy_rules",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("policy_id", sa.Integer(), nullable=False),
            sa.Column("applies_to", sa.String(length=24), nullable=False, server_default="all"),
            sa.Column("seller_type", sa.String(length=24), nullable=False, server_default="all"),
            sa.Column("city", sa.String(length=64), nullable=True),
            sa.Column("base_rate_bps", sa.Integer(), nullable=False, server_default="500"),
            sa.Column("min_fee_minor", sa.Integer(), nullable=True),
            sa.Column("max_fee_minor", sa.Integer(), nullable=True),
            sa.Column("promo_discount_bps", sa.Integer(), nullable=True),
            sa.Column("starts_at", sa.DateTime(), nullable=True),
            sa.Column("ends_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(["policy_id"], ["commission_policies.id"]),
            sa.PrimaryKeyConstraint("id"),
        )
    _create_index_if_missing(inspector, "commission_policy_rules", "ix_commission_policy_rules_policy_id", ["policy_id"])
    _create_index_if_missing(inspector, "commission_policy_rules", "ix_commission_policy_rules_applies_to", ["applies_to"])
    _create_index_if_missing(inspector, "commission_policy_rules", "ix_commission_policy_rules_seller_type", ["seller_type"])
    _create_index_if_missing(inspector, "commission_policy_rules", "ix_commission_policy_rules_city", ["city"])
    _create_index_if_missing(inspector, "commission_policy_rules", "ix_commission_policy_rules_starts_at", ["starts_at"])
    _create_index_if_missing(inspector, "commission_policy_rules", "ix_commission_policy_rules_ends_at", ["ends_at"])
    _create_index_if_missing(inspector, "commission_policy_rules", "ix_commission_policy_rules_created_at", ["created_at"])


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if inspector.has_table("commission_policy_rules"):
        _drop_index_if_exists(inspector, "commission_policy_rules", "ix_commission_policy_rules_created_at")
        _drop_index_if_exists(inspector, "commission_policy_rules", "ix_commission_policy_rules_ends_at")
        _drop_index_if_exists(inspector, "commission_policy_rules", "ix_commission_policy_rules_starts_at")
        _drop_index_if_exists(inspector, "commission_policy_rules", "ix_commission_policy_rules_city")
        _drop_index_if_exists(inspector, "commission_policy_rules", "ix_commission_policy_rules_seller_type")
        _drop_index_if_exists(inspector, "commission_policy_rules", "ix_commission_policy_rules_applies_to")
        _drop_index_if_exists(inspector, "commission_policy_rules", "ix_commission_policy_rules_policy_id")
        op.drop_table("commission_policy_rules")

    if inspector.has_table("commission_policies"):
        _drop_index_if_exists(inspector, "commission_policies", "ix_commission_policies_activated_at")
        _drop_index_if_exists(inspector, "commission_policies", "ix_commission_policies_created_at")
        _drop_index_if_exists(inspector, "commission_policies", "ix_commission_policies_created_by_admin_id")
        _drop_index_if_exists(inspector, "commission_policies", "ix_commission_policies_status")
        op.drop_table("commission_policies")

    if inspector.has_table("pricing_benchmarks"):
        _drop_index_if_exists(inspector, "pricing_benchmarks", "ix_pricing_benchmarks_updated_at")
        _drop_index_if_exists(inspector, "pricing_benchmarks", "ix_pricing_benchmarks_item_type")
        _drop_index_if_exists(inspector, "pricing_benchmarks", "ix_pricing_benchmarks_city")
        _drop_index_if_exists(inspector, "pricing_benchmarks", "ix_pricing_benchmarks_category")
        op.drop_table("pricing_benchmarks")
