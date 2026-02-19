"""add refresh tokens table

Revision ID: f5c6d7e8f9a0
Revises: f4b5c6d7e8f9
Create Date: 2026-02-13 20:40:00
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "f5c6d7e8f9a0"
down_revision = "f4b5c6d7e8f9"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    table_name = "refresh_tokens"

    if not insp.has_table(table_name):
        op.create_table(
            table_name,
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("token_hash", sa.String(length=128), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("expires_at", sa.DateTime(), nullable=False),
            sa.Column("revoked_at", sa.DateTime(), nullable=True),
            sa.Column("device_id", sa.String(length=128), nullable=True),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete=None),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("token_hash", name="uq_refresh_tokens_token_hash"),
        )

    existing_indexes = {str(idx.get("name") or "") for idx in insp.get_indexes(table_name)}
    indexes = (
        ("ix_refresh_tokens_user_id", ["user_id"]),
        ("ix_refresh_tokens_token_hash", ["token_hash"]),
        ("ix_refresh_tokens_expires_at", ["expires_at"]),
        ("ix_refresh_tokens_revoked_at", ["revoked_at"]),
    )
    for name, columns in indexes:
        if name not in existing_indexes:
            op.create_index(name, table_name, columns, unique=False)


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    table_name = "refresh_tokens"
    if not insp.has_table(table_name):
        return

    existing_indexes = {str(idx.get("name") or "") for idx in insp.get_indexes(table_name)}
    for index_name in (
        "ix_refresh_tokens_revoked_at",
        "ix_refresh_tokens_expires_at",
        "ix_refresh_tokens_token_hash",
        "ix_refresh_tokens_user_id",
    ):
        if index_name in existing_indexes:
            op.drop_index(index_name, table_name=table_name)
    op.drop_table(table_name)
