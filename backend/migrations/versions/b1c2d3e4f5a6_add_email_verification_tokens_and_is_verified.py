from alembic import op
import sqlalchemy as sa

revision = 'b1c2d3e4f5a6'
down_revision = '3cab598e1729'
branch_labels = None
depends_on = None


def _has_table(inspector, table_name: str) -> bool:
    try:
        return table_name in inspector.get_table_names()
    except Exception:
        return False


def _has_column(inspector, table_name: str, column_name: str) -> bool:
    try:
        cols = inspector.get_columns(table_name)
        return any(c.get("name") == column_name for c in cols)
    except Exception:
        return False


def _has_index(inspector, table_name: str, index_name: str) -> bool:
    try:
        idxs = inspector.get_indexes(table_name)
        return any(i.get("name") == index_name for i in idxs)
    except Exception:
        return False


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if _has_table(inspector, "users") and not _has_column(inspector, "users", "is_verified"):
        with op.batch_alter_table("users") as batch_op:
            batch_op.add_column(sa.Column("is_verified", sa.Boolean(), nullable=False, server_default=sa.text("0") if bind.dialect.name == "sqlite" else sa.false()))

    if not _has_table(inspector, "email_verification_tokens"):
        op.create_table(
            "email_verification_tokens",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("token_hash", sa.String(length=128), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP") if bind.dialect.name == "sqlite" else sa.text("now()")),
            sa.Column("expires_at", sa.DateTime(), nullable=False),
            sa.Column("used_at", sa.DateTime(), nullable=True),
        )
    if _has_table(inspector, "email_verification_tokens"):
        if not _has_index(inspector, "email_verification_tokens", "ix_email_verification_tokens_user_id"):
            op.create_index("ix_email_verification_tokens_user_id", "email_verification_tokens", ["user_id"])
        if not _has_index(inspector, "email_verification_tokens", "ix_email_verification_tokens_token_hash"):
            op.create_index("ix_email_verification_tokens_token_hash", "email_verification_tokens", ["token_hash"], unique=True)

    if not _has_table(inspector, "password_reset_tokens"):
        op.create_table(
            "password_reset_tokens",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("token_hash", sa.String(length=128), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP") if bind.dialect.name == "sqlite" else sa.text("now()")),
            sa.Column("expires_at", sa.DateTime(), nullable=False),
            sa.Column("used_at", sa.DateTime(), nullable=True),
        )
    if _has_table(inspector, "password_reset_tokens"):
        if not _has_index(inspector, "password_reset_tokens", "ix_password_reset_tokens_user_id"):
            op.create_index("ix_password_reset_tokens_user_id", "password_reset_tokens", ["user_id"])
        if not _has_index(inspector, "password_reset_tokens", "ix_password_reset_tokens_token_hash"):
            op.create_index("ix_password_reset_tokens_token_hash", "password_reset_tokens", ["token_hash"], unique=True)


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if _has_table(inspector, "password_reset_tokens"):
        op.drop_index("ix_password_reset_tokens_token_hash", table_name="password_reset_tokens")
        op.drop_index("ix_password_reset_tokens_user_id", table_name="password_reset_tokens")
        op.drop_table("password_reset_tokens")

    if _has_table(inspector, "email_verification_tokens"):
        op.drop_index("ix_email_verification_tokens_token_hash", table_name="email_verification_tokens")
        op.drop_index("ix_email_verification_tokens_user_id", table_name="email_verification_tokens")
        op.drop_table("email_verification_tokens")

    if _has_table(inspector, "users") and _has_column(inspector, "users", "is_verified"):
        with op.batch_alter_table("users") as batch_op:
            batch_op.drop_column("is_verified")
