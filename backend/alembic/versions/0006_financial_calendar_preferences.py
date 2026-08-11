"""add financial calendar preferences to profiles

Revision ID: 0006_financial_calendar
Revises: 0005_category_presets
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0006_financial_calendar"
down_revision: str | None = "0005_category_presets"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("profiles", sa.Column("month_start_day", sa.SmallInteger(), nullable=False, server_default="1"))
    op.add_column("profiles", sa.Column("week_start_day", sa.SmallInteger(), nullable=False, server_default="1"))


def downgrade() -> None:
    op.drop_column("profiles", "week_start_day")
    op.drop_column("profiles", "month_start_day")
