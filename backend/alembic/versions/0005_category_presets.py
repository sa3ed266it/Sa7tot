"""add stable category preset identity

Revision ID: 0005_category_presets
Revises: 0004_rls_hardening
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0005_category_presets"
down_revision: str | None = "0004_rls_hardening"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("categories", sa.Column("preset_key", sa.Text(), nullable=True))
    op.create_index(
        "uq_categories_user_preset",
        "categories",
        ["user_id", "preset_key"],
        unique=True,
        postgresql_where=sa.text("preset_key IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_categories_user_preset", table_name="categories")
    op.drop_column("categories", "preset_key")
