"""platform events, job runs, and feature flags json

Revision ID: f0a1b2c3d4e6
Revises: e0f1a2b3c4d5
Create Date: 2026-02-14 19:30:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "f0a1b2c3d4e6"
down_revision = "e0f1a2b3c4d5"
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


def _index_exists(bind, table_name: str, index_name: str) -> bool:
    try:
        indexes = sa.inspect(bind).get_indexes(table_name)
        return any((idx.get("name") or "") == index_name for idx in indexes)
    except Exception:
        return False


def upgrade():
    bind = op.get_bind()

    if not _table_exists(bind, "platform_events"):
        op.create_table(
            "platform_events",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("event_type", sa.String(length=80), nullable=False),
            sa.Column("actor_user_id", sa.Integer(), nullable=True),
            sa.Column("subject_type", sa.String(length=80), nullable=True),
            sa.Column("subject_id", sa.String(length=120), nullable=True),
            sa.Column("request_id", sa.String(length=80), nullable=True),
            sa.Column("idempotency_key", sa.String(length=180), nullable=True),
            sa.Column("severity", sa.String(length=16), nullable=False, server_default="INFO"),
            sa.Column("metadata_json", sa.Text(), nullable=True),
        )
    if not _index_exists(bind, "platform_events", "ix_platform_events_created_at"):
        op.create_index("ix_platform_events_created_at", "platform_events", ["created_at"], unique=False)
    if not _index_exists(bind, "platform_events", "ix_platform_events_event_type"):
        op.create_index("ix_platform_events_event_type", "platform_events", ["event_type"], unique=False)
    if not _index_exists(bind, "platform_events", "ix_platform_events_actor_user_id"):
        op.create_index("ix_platform_events_actor_user_id", "platform_events", ["actor_user_id"], unique=False)
    if not _index_exists(bind, "platform_events", "ix_platform_events_subject_type"):
        op.create_index("ix_platform_events_subject_type", "platform_events", ["subject_type"], unique=False)
    if not _index_exists(bind, "platform_events", "ix_platform_events_subject_id"):
        op.create_index("ix_platform_events_subject_id", "platform_events", ["subject_id"], unique=False)
    if not _index_exists(bind, "platform_events", "ix_platform_events_request_id"):
        op.create_index("ix_platform_events_request_id", "platform_events", ["request_id"], unique=False)
    if not _index_exists(bind, "platform_events", "ix_platform_events_idempotency_key"):
        op.create_index("ix_platform_events_idempotency_key", "platform_events", ["idempotency_key"], unique=True)
    if not _index_exists(bind, "platform_events", "ix_platform_events_severity"):
        op.create_index("ix_platform_events_severity", "platform_events", ["severity"], unique=False)

    if not _table_exists(bind, "job_runs"):
        op.create_table(
            "job_runs",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("job_name", sa.String(length=64), nullable=False),
            sa.Column("ran_at", sa.DateTime(), nullable=False),
            sa.Column("ok", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("duration_ms", sa.Integer(), nullable=True),
            sa.Column("error", sa.Text(), nullable=True),
        )
    if not _index_exists(bind, "job_runs", "ix_job_runs_job_name"):
        op.create_index("ix_job_runs_job_name", "job_runs", ["job_name"], unique=False)
    if not _index_exists(bind, "job_runs", "ix_job_runs_ran_at"):
        op.create_index("ix_job_runs_ran_at", "job_runs", ["ran_at"], unique=False)
    if not _index_exists(bind, "job_runs", "ix_job_runs_ok"):
        op.create_index("ix_job_runs_ok", "job_runs", ["ok"], unique=False)

    if _table_exists(bind, "autopilot_settings") and not _column_exists(bind, "autopilot_settings", "feature_flags_json"):
        with op.batch_alter_table("autopilot_settings") as batch:
            batch.add_column(sa.Column("feature_flags_json", sa.Text(), nullable=False, server_default="{}"))

    if _table_exists(bind, "autopilot_settings"):
        op.execute(
            sa.text(
                "UPDATE autopilot_settings SET feature_flags_json='{}' "
                "WHERE feature_flags_json IS NULL OR TRIM(feature_flags_json)=''"
            )
        )


def downgrade():
    bind = op.get_bind()
    if _table_exists(bind, "autopilot_settings") and _column_exists(bind, "autopilot_settings", "feature_flags_json"):
        with op.batch_alter_table("autopilot_settings") as batch:
            batch.drop_column("feature_flags_json")

    if _table_exists(bind, "job_runs"):
        for idx in ("ix_job_runs_ok", "ix_job_runs_ran_at", "ix_job_runs_job_name"):
            try:
                op.drop_index(idx, table_name="job_runs")
            except Exception:
                pass
        op.drop_table("job_runs")

    if _table_exists(bind, "platform_events"):
        for idx in (
            "ix_platform_events_severity",
            "ix_platform_events_idempotency_key",
            "ix_platform_events_request_id",
            "ix_platform_events_subject_id",
            "ix_platform_events_subject_type",
            "ix_platform_events_actor_user_id",
            "ix_platform_events_event_type",
            "ix_platform_events_created_at",
        ):
            try:
                op.drop_index(idx, table_name="platform_events")
            except Exception:
                pass
        op.drop_table("platform_events")
