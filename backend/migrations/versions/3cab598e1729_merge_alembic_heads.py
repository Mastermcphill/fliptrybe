"""Merge alembic heads

Revision ID: 3cab598e1729
Revises: 622c53e5e088, d0e1f2a3b4c5
Create Date: 2026-02-07 10:49:17.738339

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '3cab598e1729'
down_revision = ('622c53e5e088', 'd0e1f2a3b4c5')
branch_labels = None
depends_on = None


def upgrade():
    pass


def downgrade():
    pass
