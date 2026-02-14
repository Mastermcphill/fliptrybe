"""referrals growth analytics

Revision ID: f6b7c8d9e0f1
Revises: f5c6d7e8f9a0
Create Date: 2026-02-14 21:40:00.000000
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "f6b7c8d9e0f1"
down_revision = "f5c6d7e8f9a0"
branch_labels = None
depends_on = None


def _has_column(inspector, table_name: str, column_name: str) -> bool:
    try:
        cols = inspector.get_columns(table_name)
    except Exception:
        return False
    return any((c.get("name") or "").strip().lower() == column_name.lower() for c in cols)


def _has_table(inspector, table_name: str) -> bool:
    try:
        return table_name in inspector.get_table_names()
    except Exception:
        return False


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if _has_table(inspector, "users"):
        if not _has_column(inspector, "users", "referral_code"):
            with op.batch_alter_table("users", schema=None) as batch_op:
                batch_op.add_column(sa.Column("referral_code", sa.String(length=32), nullable=True))
        if not _has_column(inspector, "users", "referred_by"):
            with op.batch_alter_table("users", schema=None) as batch_op:
                batch_op.add_column(sa.Column("referred_by", sa.Integer(), nullable=True))
                batch_op.create_foreign_key(
                    "fk_users_referred_by_users",
                    "users",
                    ["referred_by"],
                    ["id"],
                )
        with op.batch_alter_table("users", schema=None) as batch_op:
            try:
                batch_op.create_unique_constraint("uq_users_referral_code", ["referral_code"])
            except Exception:
                pass
            try:
                batch_op.create_index("ix_users_referral_code", ["referral_code"], unique=False)
            except Exception:
                pass
            try:
                batch_op.create_index("ix_users_referred_by", ["referred_by"], unique=False)
            except Exception:
                pass

    inspector = sa.inspect(bind)
    if not _has_table(inspector, "referrals"):
        op.create_table(
            "referrals",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("referrer_user_id", sa.Integer(), nullable=False),
            sa.Column("referred_user_id", sa.Integer(), nullable=False),
            sa.Column("referral_code", sa.String(length=32), nullable=False),
            sa.Column("status", sa.String(length=24), nullable=False, server_default="pending"),
            sa.Column("reward_amount_minor", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("reward_reference", sa.String(length=80), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("completed_at", sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(["referrer_user_id"], ["users.id"]),
            sa.ForeignKeyConstraint(["referred_user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("referred_user_id", name="uq_referrals_referred_user"),
            sa.UniqueConstraint("reward_reference", name="uq_referrals_reward_reference"),
        )
        op.create_index("ix_referrals_referrer_user_id", "referrals", ["referrer_user_id"], unique=False)
        op.create_index("ix_referrals_referred_user_id", "referrals", ["referred_user_id"], unique=False)
        op.create_index("ix_referrals_referral_code", "referrals", ["referral_code"], unique=False)
        op.create_index("ix_referrals_status", "referrals", ["status"], unique=False)
        op.create_index("ix_referrals_created_at", "referrals", ["created_at"], unique=False)

    # Backfill referral_code for existing users.
    rows = bind.execute(sa.text("SELECT id, referral_code FROM users")).fetchall()
    for row in rows:
        uid = int(row[0])
        code = (row[1] or "").strip() if len(row) > 1 else ""
        if code:
            continue
        generated = f"FT{uid:06d}"
        bind.execute(
            sa.text("UPDATE users SET referral_code = :code WHERE id = :uid"),
            {"code": generated, "uid": uid},
        )


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if _has_table(inspector, "referrals"):
        try:
            op.drop_index("ix_referrals_created_at", table_name="referrals")
        except Exception:
            pass
        try:
            op.drop_index("ix_referrals_status", table_name="referrals")
        except Exception:
            pass
        try:
            op.drop_index("ix_referrals_referral_code", table_name="referrals")
        except Exception:
            pass
        try:
            op.drop_index("ix_referrals_referred_user_id", table_name="referrals")
        except Exception:
            pass
        try:
            op.drop_index("ix_referrals_referrer_user_id", table_name="referrals")
        except Exception:
            pass
        op.drop_table("referrals")

    inspector = sa.inspect(bind)
    if _has_table(inspector, "users"):
        with op.batch_alter_table("users", schema=None) as batch_op:
            try:
                batch_op.drop_index("ix_users_referred_by")
            except Exception:
                pass
            try:
                batch_op.drop_index("ix_users_referral_code")
            except Exception:
                pass
            try:
                batch_op.drop_constraint("uq_users_referral_code", type_="unique")
            except Exception:
                pass
            try:
                batch_op.drop_constraint("fk_users_referred_by_users", type_="foreignkey")
            except Exception:
                pass
            if _has_column(sa.inspect(bind), "users", "referred_by"):
                batch_op.drop_column("referred_by")
            if _has_column(sa.inspect(bind), "users", "referral_code"):
                batch_op.drop_column("referral_code")
