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

    if not inspector.has_table("autopilot_snapshots"):
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
    _create_index_if_missing(inspector, "autopilot_snapshots", "ix_autopilot_snapshots_window_days", ["window_days"])
    _create_index_if_missing(inspector, "autopilot_snapshots", "ix_autopilot_snapshots_generated_at", ["generated_at"])
    _create_index_if_missing(inspector, "autopilot_snapshots", "ix_autopilot_snapshots_created_by_admin_id", ["created_by_admin_id"])
    _create_index_if_missing(inspector, "autopilot_snapshots", "ix_autopilot_snapshots_hash_key", ["hash_key"])
    _create_index_if_missing(inspector, "autopilot_snapshots", "ix_autopilot_snapshots_draft_policy_id", ["draft_policy_id"])

    if not inspector.has_table("autopilot_recommendations"):
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
    _create_index_if_missing(inspector, "autopilot_recommendations", "ix_autopilot_recommendations_snapshot_id", ["snapshot_id"])
    _create_index_if_missing(inspector, "autopilot_recommendations", "ix_autopilot_recommendations_applies_to", ["applies_to"])
    _create_index_if_missing(inspector, "autopilot_recommendations", "ix_autopilot_recommendations_seller_type", ["seller_type"])
    _create_index_if_missing(inspector, "autopilot_recommendations", "ix_autopilot_recommendations_city", ["city"])
    _create_index_if_missing(inspector, "autopilot_recommendations", "ix_autopilot_recommendations_status", ["status"])
    _create_index_if_missing(inspector, "autopilot_recommendations", "ix_autopilot_recommendations_created_at", ["created_at"])

    if not inspector.has_table("autopilot_events"):
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
    _create_index_if_missing(inspector, "autopilot_events", "ix_autopilot_events_event_type", ["event_type"])
    _create_index_if_missing(inspector, "autopilot_events", "ix_autopilot_events_admin_id", ["admin_id"])
    _create_index_if_missing(inspector, "autopilot_events", "ix_autopilot_events_created_at", ["created_at"])


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if inspector.has_table("autopilot_events"):
        _drop_index_if_exists(inspector, "autopilot_events", "ix_autopilot_events_created_at")
        _drop_index_if_exists(inspector, "autopilot_events", "ix_autopilot_events_admin_id")
        _drop_index_if_exists(inspector, "autopilot_events", "ix_autopilot_events_event_type")
        op.drop_table("autopilot_events")

    if inspector.has_table("autopilot_recommendations"):
        _drop_index_if_exists(inspector, "autopilot_recommendations", "ix_autopilot_recommendations_created_at")
        _drop_index_if_exists(inspector, "autopilot_recommendations", "ix_autopilot_recommendations_status")
        _drop_index_if_exists(inspector, "autopilot_recommendations", "ix_autopilot_recommendations_city")
        _drop_index_if_exists(inspector, "autopilot_recommendations", "ix_autopilot_recommendations_seller_type")
        _drop_index_if_exists(inspector, "autopilot_recommendations", "ix_autopilot_recommendations_applies_to")
        _drop_index_if_exists(inspector, "autopilot_recommendations", "ix_autopilot_recommendations_snapshot_id")
        op.drop_table("autopilot_recommendations")

    if inspector.has_table("autopilot_snapshots"):
        _drop_index_if_exists(inspector, "autopilot_snapshots", "ix_autopilot_snapshots_draft_policy_id")
        _drop_index_if_exists(inspector, "autopilot_snapshots", "ix_autopilot_snapshots_hash_key")
        _drop_index_if_exists(inspector, "autopilot_snapshots", "ix_autopilot_snapshots_created_by_admin_id")
        _drop_index_if_exists(inspector, "autopilot_snapshots", "ix_autopilot_snapshots_generated_at")
        _drop_index_if_exists(inspector, "autopilot_snapshots", "ix_autopilot_snapshots_window_days")
        op.drop_table("autopilot_snapshots")
