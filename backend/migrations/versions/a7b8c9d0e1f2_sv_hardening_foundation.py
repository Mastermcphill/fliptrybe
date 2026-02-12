"""sv hardening foundation

Revision ID: a7b8c9d0e1f2
Revises: ff6a7b8c9d01
Create Date: 2026-02-13 00:20:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "a7b8c9d0e1f2"
down_revision = "ff6a7b8c9d01"
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
        rows = sa.inspect(bind).get_indexes(table_name)
        return any((r.get("name") or "") == index_name for r in rows)
    except Exception:
        return False


def _add_autopilot_flags(bind):
    if not _table_exists(bind, "autopilot_settings"):
        return
    add = []
    if not _column_exists(bind, "autopilot_settings", "search_v2_mode"):
        add.append(sa.Column("search_v2_mode", sa.String(length=16), nullable=False, server_default="off"))
    if not _column_exists(bind, "autopilot_settings", "payments_allow_legacy_fallback"):
        add.append(sa.Column("payments_allow_legacy_fallback", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists(bind, "autopilot_settings", "otel_enabled"):
        add.append(sa.Column("otel_enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists(bind, "autopilot_settings", "rate_limit_enabled"):
        add.append(sa.Column("rate_limit_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")))
    if add:
        with op.batch_alter_table("autopilot_settings") as batch_op:
            for col in add:
                batch_op.add_column(col)
    try:
        op.execute("UPDATE autopilot_settings SET search_v2_mode='off' WHERE search_v2_mode IS NULL")
    except Exception:
        pass


def _expand_webhook_events(bind):
    if not _table_exists(bind, "webhook_events"):
        return
    add = []
    if not _column_exists(bind, "webhook_events", "status"):
        add.append(sa.Column("status", sa.String(length=32), nullable=False, server_default="received"))
    if not _column_exists(bind, "webhook_events", "processed_at"):
        add.append(sa.Column("processed_at", sa.DateTime(), nullable=True))
    if not _column_exists(bind, "webhook_events", "request_id"):
        add.append(sa.Column("request_id", sa.String(length=64), nullable=True))
    if not _column_exists(bind, "webhook_events", "payload_hash"):
        add.append(sa.Column("payload_hash", sa.String(length=128), nullable=True))
    if not _column_exists(bind, "webhook_events", "payload_json"):
        add.append(sa.Column("payload_json", sa.Text(), nullable=True))
    if not _column_exists(bind, "webhook_events", "error"):
        add.append(sa.Column("error", sa.Text(), nullable=True))
    if add:
        with op.batch_alter_table("webhook_events") as batch_op:
            for col in add:
                batch_op.add_column(col)
    if not _index_exists(bind, "webhook_events", "ix_webhook_events_processed_at"):
        op.create_index("ix_webhook_events_processed_at", "webhook_events", ["processed_at"], unique=False)


def _expand_payment_intents(bind):
    if not _table_exists(bind, "payment_intents"):
        return
    if not _column_exists(bind, "payment_intents", "updated_at"):
        with op.batch_alter_table("payment_intents") as batch_op:
            batch_op.add_column(sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")))
    try:
        op.execute("UPDATE payment_intents SET updated_at=created_at WHERE updated_at IS NULL")
    except Exception:
        pass


def _create_transition_tables(bind):
    if not _table_exists(bind, "payment_intent_transitions"):
        op.create_table(
            "payment_intent_transitions",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("intent_id", sa.Integer(), nullable=False),
            sa.Column("from_status", sa.String(length=32), nullable=False, server_default=""),
            sa.Column("to_status", sa.String(length=32), nullable=False),
            sa.Column("actor_type", sa.String(length=32), nullable=False, server_default="system"),
            sa.Column("actor_id", sa.Integer(), nullable=True),
            sa.Column("idempotency_key", sa.String(length=160), nullable=False),
            sa.Column("reason", sa.String(length=240), nullable=True),
            sa.Column("metadata_json", sa.Text(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
            sa.UniqueConstraint("intent_id", "idempotency_key", name="uq_pi_transition_intent_key"),
        )
        op.create_index("ix_pi_transitions_intent_id", "payment_intent_transitions", ["intent_id"], unique=False)

    if not _table_exists(bind, "escrow_transitions"):
        op.create_table(
            "escrow_transitions",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("escrow_id", sa.String(length=64), nullable=False),
            sa.Column("order_id", sa.Integer(), nullable=False),
            sa.Column("from_status", sa.String(length=32), nullable=False, server_default=""),
            sa.Column("to_status", sa.String(length=32), nullable=False),
            sa.Column("actor_type", sa.String(length=32), nullable=False, server_default="system"),
            sa.Column("actor_id", sa.Integer(), nullable=True),
            sa.Column("idempotency_key", sa.String(length=160), nullable=False),
            sa.Column("reason", sa.String(length=240), nullable=True),
            sa.Column("metadata_json", sa.Text(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
            sa.UniqueConstraint("order_id", "idempotency_key", name="uq_escrow_transition_order_key"),
        )
        op.create_index("ix_escrow_transitions_order_id", "escrow_transitions", ["order_id"], unique=False)
        op.create_index("ix_escrow_transitions_escrow_id", "escrow_transitions", ["escrow_id"], unique=False)

    if not _table_exists(bind, "risk_events"):
        op.create_table(
            "risk_events",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("action", sa.String(length=80), nullable=False),
            sa.Column("score", sa.Float(), nullable=False, server_default="0"),
            sa.Column("flags_json", sa.Text(), nullable=True),
            sa.Column("decision", sa.String(length=64), nullable=False, server_default="allow"),
            sa.Column("reason_code", sa.String(length=120), nullable=True),
            sa.Column("user_id", sa.Integer(), nullable=True),
            sa.Column("request_id", sa.String(length=64), nullable=True),
            sa.Column("context_json", sa.Text(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        )
        op.create_index("ix_risk_events_action", "risk_events", ["action"], unique=False)
        op.create_index("ix_risk_events_reason_code", "risk_events", ["reason_code"], unique=False)
        op.create_index("ix_risk_events_created_at", "risk_events", ["created_at"], unique=False)

    if not _table_exists(bind, "reconciliation_reports"):
        op.create_table(
            "reconciliation_reports",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("scope", sa.String(length=64), nullable=False, server_default="wallet_ledger"),
            sa.Column("since", sa.String(length=64), nullable=True),
            sa.Column("summary_json", sa.Text(), nullable=True),
            sa.Column("drift_count", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_by", sa.Integer(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        )
        op.create_index("ix_reconciliation_reports_created_at", "reconciliation_reports", ["created_at"], unique=False)


def _patch_search_v2(bind):
    if not _table_exists(bind, "listings"):
        return
    dialect = bind.dialect.name

    if not _column_exists(bind, "listings", "search_vector"):
        if dialect == "postgresql":
            op.execute("ALTER TABLE listings ADD COLUMN IF NOT EXISTS search_vector tsvector")
        else:
            with op.batch_alter_table("listings") as batch_op:
                batch_op.add_column(sa.Column("search_vector", sa.Text(), nullable=True))

    if dialect == "postgresql":
        try:
            op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
        except Exception:
            pass
        try:
            op.execute(
                """
                UPDATE listings
                SET search_vector = to_tsvector(
                    'english',
                    coalesce(title,'') || ' ' ||
                    coalesce(description,'') || ' ' ||
                    coalesce(category,'') || ' ' ||
                    coalesce(state,'') || ' ' ||
                    coalesce(city,'')
                )
                WHERE search_vector IS NULL
                """
            )
        except Exception:
            pass
        try:
            op.execute(
                "CREATE INDEX IF NOT EXISTS ix_listings_search_vector_gin ON listings USING GIN (search_vector)"
            )
        except Exception:
            pass
        try:
            op.execute(
                "CREATE INDEX IF NOT EXISTS ix_listings_title_trgm ON listings USING GIN (title gin_trgm_ops)"
            )
        except Exception:
            pass
        try:
            op.execute(
                "CREATE INDEX IF NOT EXISTS ix_listings_description_trgm ON listings USING GIN (description gin_trgm_ops)"
            )
        except Exception:
            pass


def upgrade():
    bind = op.get_bind()
    _add_autopilot_flags(bind)
    _expand_webhook_events(bind)
    _expand_payment_intents(bind)
    _create_transition_tables(bind)
    _patch_search_v2(bind)


def downgrade():
    # Non-destructive downgrade for drift-safe environments.
    pass
