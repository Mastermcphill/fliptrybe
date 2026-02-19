"""add image fingerprints table

Revision ID: f4b5c6d7e8f9
Revises: f0a1b2c3d4e6
Create Date: 2026-02-13 13:55:00
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "f4b5c6d7e8f9"
down_revision = "f0a1b2c3d4e6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    table_name = "image_fingerprints"

    if not insp.has_table(table_name):
        op.create_table(
            table_name,
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("hash_type", sa.String(length=24), nullable=False, server_default="phash64"),
            sa.Column("hash_hex", sa.String(length=32), nullable=False),
            sa.Column("hash_int", sa.BigInteger(), nullable=False),
            sa.Column("source", sa.String(length=32), nullable=False, server_default="unknown"),
            sa.Column("cloudinary_public_id", sa.String(length=255), nullable=True),
            sa.Column("image_url", sa.String(length=1024), nullable=False, server_default=""),
            sa.Column("listing_id", sa.Integer(), nullable=True),
            sa.Column("shortlet_id", sa.Integer(), nullable=True),
            sa.Column("uploader_user_id", sa.Integer(), nullable=True),
            sa.ForeignKeyConstraint(["listing_id"], ["listings.id"], ondelete=None),
            sa.ForeignKeyConstraint(["shortlet_id"], ["shortlets.id"], ondelete=None),
            sa.ForeignKeyConstraint(["uploader_user_id"], ["users.id"], ondelete=None),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("hash_hex", name="uq_image_fingerprints_hash_hex"),
        )

    existing_indexes = {str(idx.get("name") or "") for idx in insp.get_indexes(table_name)}
    indexes = (
        ("ix_image_fingerprints_created_at", ["created_at"]),
        ("ix_image_fingerprints_hash_hex", ["hash_hex"]),
        ("ix_image_fingerprints_hash_int", ["hash_int"]),
        ("ix_image_fingerprints_cloudinary_public_id", ["cloudinary_public_id"]),
        ("ix_image_fingerprints_listing_id", ["listing_id"]),
        ("ix_image_fingerprints_shortlet_id", ["shortlet_id"]),
        ("ix_image_fingerprints_uploader_user_id", ["uploader_user_id"]),
    )
    for name, columns in indexes:
        if name not in existing_indexes:
            op.create_index(name, table_name, columns, unique=False)


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    table_name = "image_fingerprints"
    if not insp.has_table(table_name):
        return

    existing_indexes = {str(idx.get("name") or "") for idx in insp.get_indexes(table_name)}
    for index_name in (
        "ix_image_fingerprints_uploader_user_id",
        "ix_image_fingerprints_shortlet_id",
        "ix_image_fingerprints_listing_id",
        "ix_image_fingerprints_cloudinary_public_id",
        "ix_image_fingerprints_hash_int",
        "ix_image_fingerprints_hash_hex",
        "ix_image_fingerprints_created_at",
    ):
        if index_name in existing_indexes:
            op.drop_index(index_name, table_name=table_name)
    op.drop_table(table_name)
