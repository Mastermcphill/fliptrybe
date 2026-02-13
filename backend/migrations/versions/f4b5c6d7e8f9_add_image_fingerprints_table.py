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
    op.create_table(
        "image_fingerprints",
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
    op.create_index("ix_image_fingerprints_created_at", "image_fingerprints", ["created_at"], unique=False)
    op.create_index("ix_image_fingerprints_hash_hex", "image_fingerprints", ["hash_hex"], unique=False)
    op.create_index("ix_image_fingerprints_hash_int", "image_fingerprints", ["hash_int"], unique=False)
    op.create_index("ix_image_fingerprints_cloudinary_public_id", "image_fingerprints", ["cloudinary_public_id"], unique=False)
    op.create_index("ix_image_fingerprints_listing_id", "image_fingerprints", ["listing_id"], unique=False)
    op.create_index("ix_image_fingerprints_shortlet_id", "image_fingerprints", ["shortlet_id"], unique=False)
    op.create_index("ix_image_fingerprints_uploader_user_id", "image_fingerprints", ["uploader_user_id"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_image_fingerprints_uploader_user_id", table_name="image_fingerprints")
    op.drop_index("ix_image_fingerprints_shortlet_id", table_name="image_fingerprints")
    op.drop_index("ix_image_fingerprints_listing_id", table_name="image_fingerprints")
    op.drop_index("ix_image_fingerprints_cloudinary_public_id", table_name="image_fingerprints")
    op.drop_index("ix_image_fingerprints_hash_int", table_name="image_fingerprints")
    op.drop_index("ix_image_fingerprints_hash_hex", table_name="image_fingerprints")
    op.drop_index("ix_image_fingerprints_created_at", table_name="image_fingerprints")
    op.drop_table("image_fingerprints")
