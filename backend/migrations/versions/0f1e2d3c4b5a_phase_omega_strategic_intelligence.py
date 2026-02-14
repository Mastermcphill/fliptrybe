"""phase omega strategic intelligence tables

Revision ID: 0f1e2d3c4b5a
Revises: fad2c3b4e5f6
Create Date: 2026-02-15 10:30:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "0f1e2d3c4b5a"
down_revision = "fad2c3b4e5f6"
branch_labels = None
depends_on = None


def _table_exists(bind, table_name: str) -> bool:
    try:
        return sa.inspect(bind).has_table(table_name)
    except Exception:
        return False


def upgrade():
    bind = op.get_bind()

    if not _table_exists(bind, "elasticity_snapshots"):
        op.create_table(
            "elasticity_snapshots",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("category", sa.String(length=24), nullable=False),
            sa.Column("city", sa.String(length=64), nullable=False, server_default="all"),
            sa.Column("seller_type", sa.String(length=24), nullable=False, server_default="all"),
            sa.Column("window_days", sa.Integer(), nullable=False, server_default="90"),
            sa.Column("sample_size", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("elasticity_coefficient", sa.Float(), nullable=False, server_default="0"),
            sa.Column("confidence", sa.String(length=16), nullable=False, server_default="low"),
            sa.Column("recommendation_shift_pct", sa.Float(), nullable=False, server_default="0"),
            sa.Column("metrics_json", sa.Text(), nullable=False, server_default="{}"),
            sa.Column("hash_key", sa.String(length=96), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("hash_key", name="uq_elasticity_snapshot_hash"),
        )
        op.create_index("ix_elasticity_snapshots_category", "elasticity_snapshots", ["category"], unique=False)
        op.create_index("ix_elasticity_snapshots_city", "elasticity_snapshots", ["city"], unique=False)
        op.create_index("ix_elasticity_snapshots_seller_type", "elasticity_snapshots", ["seller_type"], unique=False)
        op.create_index("ix_elasticity_snapshots_hash_key", "elasticity_snapshots", ["hash_key"], unique=False)
        op.create_index("ix_elasticity_snapshots_created_at", "elasticity_snapshots", ["created_at"], unique=False)

    if not _table_exists(bind, "fraud_flags"):
        op.create_table(
            "fraud_flags",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("score", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("reasons_json", sa.Text(), nullable=False, server_default="{}"),
            sa.Column("status", sa.String(length=24), nullable=False, server_default="open"),
            sa.Column("reviewed_by_admin_id", sa.Integer(), nullable=True),
            sa.Column("reviewed_at", sa.DateTime(), nullable=True),
            sa.Column("action_note", sa.String(length=240), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(["reviewed_by_admin_id"], ["users.id"]),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index("ix_fraud_flags_user_id", "fraud_flags", ["user_id"], unique=False)
        op.create_index("ix_fraud_flags_score", "fraud_flags", ["score"], unique=False)
        op.create_index("ix_fraud_flags_status", "fraud_flags", ["status"], unique=False)
        op.create_index("ix_fraud_flags_created_at", "fraud_flags", ["created_at"], unique=False)
        op.create_index("ix_fraud_flags_reviewed_by_admin_id", "fraud_flags", ["reviewed_by_admin_id"], unique=False)


def downgrade():
    bind = op.get_bind()
    if _table_exists(bind, "fraud_flags"):
        op.drop_index("ix_fraud_flags_reviewed_by_admin_id", table_name="fraud_flags")
        op.drop_index("ix_fraud_flags_created_at", table_name="fraud_flags")
        op.drop_index("ix_fraud_flags_status", table_name="fraud_flags")
        op.drop_index("ix_fraud_flags_score", table_name="fraud_flags")
        op.drop_index("ix_fraud_flags_user_id", table_name="fraud_flags")
        op.drop_table("fraud_flags")
    if _table_exists(bind, "elasticity_snapshots"):
        op.drop_index("ix_elasticity_snapshots_created_at", table_name="elasticity_snapshots")
        op.drop_index("ix_elasticity_snapshots_hash_key", table_name="elasticity_snapshots")
        op.drop_index("ix_elasticity_snapshots_seller_type", table_name="elasticity_snapshots")
        op.drop_index("ix_elasticity_snapshots_city", table_name="elasticity_snapshots")
        op.drop_index("ix_elasticity_snapshots_category", table_name="elasticity_snapshots")
        op.drop_table("elasticity_snapshots")
