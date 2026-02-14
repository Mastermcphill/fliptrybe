"""commission autopilot snapshots and recommendations

Revision ID: fad2c3b4e5f6
Revises: f7d8e9a0b1c2
Create Date: 2026-02-14 23:59:00.000000
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "fad2c3b4e5f6"
down_revision = "f7d8e9a0b1c2"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "autopilot_snapshots",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("window_days", sa.Integer(), nullable=False, server_default="30"),
        sa.Column("generated_at", sa.DateTime(), nullable=False),
        sa.Column("metrics_json", sa.Text(), nullable=False, server_default="{}"),
        sa.Column("created_by_admin_id", sa.Integer(), nullable=True),
        sa.Column("hash_key", sa.String(length=96), nullable=False),
        sa.Column("draft_policy_id", sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(["created_by_admin_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["draft_policy_id"], ["commission_policies.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("hash_key", name="uq_autopilot_snapshot_hash"),
    )
    op.create_index("ix_autopilot_snapshots_window_days", "autopilot_snapshots", ["window_days"], unique=False)
    op.create_index("ix_autopilot_snapshots_generated_at", "autopilot_snapshots", ["generated_at"], unique=False)
    op.create_index("ix_autopilot_snapshots_created_by_admin_id", "autopilot_snapshots", ["created_by_admin_id"], unique=False)
    op.create_index("ix_autopilot_snapshots_hash_key", "autopilot_snapshots", ["hash_key"], unique=False)
    op.create_index("ix_autopilot_snapshots_draft_policy_id", "autopilot_snapshots", ["draft_policy_id"], unique=False)

    op.create_table(
        "autopilot_recommendations",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("snapshot_id", sa.Integer(), nullable=False),
        sa.Column("applies_to", sa.String(length=24), nullable=False, server_default="declutter"),
        sa.Column("seller_type", sa.String(length=24), nullable=False, server_default="all"),
        sa.Column("city", sa.String(length=64), nullable=True),
        sa.Column("recommendation_json", sa.Text(), nullable=False, server_default="{}"),
        sa.Column("status", sa.String(length=24), nullable=False, server_default="new"),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["snapshot_id"], ["autopilot_snapshots.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_autopilot_recommendations_snapshot_id", "autopilot_recommendations", ["snapshot_id"], unique=False)
    op.create_index("ix_autopilot_recommendations_applies_to", "autopilot_recommendations", ["applies_to"], unique=False)
    op.create_index("ix_autopilot_recommendations_seller_type", "autopilot_recommendations", ["seller_type"], unique=False)
    op.create_index("ix_autopilot_recommendations_city", "autopilot_recommendations", ["city"], unique=False)
    op.create_index("ix_autopilot_recommendations_status", "autopilot_recommendations", ["status"], unique=False)
    op.create_index("ix_autopilot_recommendations_created_at", "autopilot_recommendations", ["created_at"], unique=False)

    op.create_table(
        "autopilot_events",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("event_type", sa.String(length=40), nullable=False),
        sa.Column("admin_id", sa.Integer(), nullable=True),
        sa.Column("payload_json", sa.Text(), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["admin_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_autopilot_events_event_type", "autopilot_events", ["event_type"], unique=False)
    op.create_index("ix_autopilot_events_admin_id", "autopilot_events", ["admin_id"], unique=False)
    op.create_index("ix_autopilot_events_created_at", "autopilot_events", ["created_at"], unique=False)


def downgrade():
    op.drop_index("ix_autopilot_events_created_at", table_name="autopilot_events")
    op.drop_index("ix_autopilot_events_admin_id", table_name="autopilot_events")
    op.drop_index("ix_autopilot_events_event_type", table_name="autopilot_events")
    op.drop_table("autopilot_events")

    op.drop_index("ix_autopilot_recommendations_created_at", table_name="autopilot_recommendations")
    op.drop_index("ix_autopilot_recommendations_status", table_name="autopilot_recommendations")
    op.drop_index("ix_autopilot_recommendations_city", table_name="autopilot_recommendations")
    op.drop_index("ix_autopilot_recommendations_seller_type", table_name="autopilot_recommendations")
    op.drop_index("ix_autopilot_recommendations_applies_to", table_name="autopilot_recommendations")
    op.drop_index("ix_autopilot_recommendations_snapshot_id", table_name="autopilot_recommendations")
    op.drop_table("autopilot_recommendations")

    op.drop_index("ix_autopilot_snapshots_draft_policy_id", table_name="autopilot_snapshots")
    op.drop_index("ix_autopilot_snapshots_hash_key", table_name="autopilot_snapshots")
    op.drop_index("ix_autopilot_snapshots_created_by_admin_id", table_name="autopilot_snapshots")
    op.drop_index("ix_autopilot_snapshots_generated_at", table_name="autopilot_snapshots")
    op.drop_index("ix_autopilot_snapshots_window_days", table_name="autopilot_snapshots")
    op.drop_table("autopilot_snapshots")
