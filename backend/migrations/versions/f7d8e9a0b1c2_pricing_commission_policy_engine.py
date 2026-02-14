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


def upgrade():
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
    op.create_index("ix_pricing_benchmarks_category", "pricing_benchmarks", ["category"], unique=False)
    op.create_index("ix_pricing_benchmarks_city", "pricing_benchmarks", ["city"], unique=False)
    op.create_index("ix_pricing_benchmarks_item_type", "pricing_benchmarks", ["item_type"], unique=False)
    op.create_index("ix_pricing_benchmarks_updated_at", "pricing_benchmarks", ["updated_at"], unique=False)

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
    op.create_index("ix_commission_policies_status", "commission_policies", ["status"], unique=False)
    op.create_index("ix_commission_policies_created_by_admin_id", "commission_policies", ["created_by_admin_id"], unique=False)
    op.create_index("ix_commission_policies_created_at", "commission_policies", ["created_at"], unique=False)
    op.create_index("ix_commission_policies_activated_at", "commission_policies", ["activated_at"], unique=False)

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
    op.create_index("ix_commission_policy_rules_policy_id", "commission_policy_rules", ["policy_id"], unique=False)
    op.create_index("ix_commission_policy_rules_applies_to", "commission_policy_rules", ["applies_to"], unique=False)
    op.create_index("ix_commission_policy_rules_seller_type", "commission_policy_rules", ["seller_type"], unique=False)
    op.create_index("ix_commission_policy_rules_city", "commission_policy_rules", ["city"], unique=False)
    op.create_index("ix_commission_policy_rules_starts_at", "commission_policy_rules", ["starts_at"], unique=False)
    op.create_index("ix_commission_policy_rules_ends_at", "commission_policy_rules", ["ends_at"], unique=False)
    op.create_index("ix_commission_policy_rules_created_at", "commission_policy_rules", ["created_at"], unique=False)


def downgrade():
    op.drop_index("ix_commission_policy_rules_created_at", table_name="commission_policy_rules")
    op.drop_index("ix_commission_policy_rules_ends_at", table_name="commission_policy_rules")
    op.drop_index("ix_commission_policy_rules_starts_at", table_name="commission_policy_rules")
    op.drop_index("ix_commission_policy_rules_city", table_name="commission_policy_rules")
    op.drop_index("ix_commission_policy_rules_seller_type", table_name="commission_policy_rules")
    op.drop_index("ix_commission_policy_rules_applies_to", table_name="commission_policy_rules")
    op.drop_index("ix_commission_policy_rules_policy_id", table_name="commission_policy_rules")
    op.drop_table("commission_policy_rules")

    op.drop_index("ix_commission_policies_activated_at", table_name="commission_policies")
    op.drop_index("ix_commission_policies_created_at", table_name="commission_policies")
    op.drop_index("ix_commission_policies_created_by_admin_id", table_name="commission_policies")
    op.drop_index("ix_commission_policies_status", table_name="commission_policies")
    op.drop_table("commission_policies")

    op.drop_index("ix_pricing_benchmarks_updated_at", table_name="pricing_benchmarks")
    op.drop_index("ix_pricing_benchmarks_item_type", table_name="pricing_benchmarks")
    op.drop_index("ix_pricing_benchmarks_city", table_name="pricing_benchmarks")
    op.drop_index("ix_pricing_benchmarks_category", table_name="pricing_benchmarks")
    op.drop_table("pricing_benchmarks")
