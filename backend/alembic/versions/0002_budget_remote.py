"""add remote budget tables

Revision ID: 0002_budget_remote
Revises: 0001_backend_foundation
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0002_budget_remote"
down_revision: str | None = "0001_backend_foundation"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _columns(table: str, *, category: bool = False) -> None:
    columns = [
        sa.Column("id", sa.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", sa.UUID(as_uuid=True), nullable=False),
    ]
    if category:
        columns.append(sa.Column("category_id", sa.UUID(as_uuid=True), nullable=False))
    columns.extend(
        [
            sa.Column("amount_minor", sa.BigInteger(), nullable=False),
            sa.Column("currency_code", sa.String(length=3), nullable=False),
            sa.Column("currency_exponent", sa.SmallInteger(), nullable=False, server_default="2"),
            sa.Column("period_type", sa.Text(), nullable=False),
            sa.Column("period_start", sa.Date(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        ]
    )
    constraints = [
        sa.CheckConstraint("amount_minor >= 0", name=f"ck_{table}_amount_nonnegative"),
        sa.CheckConstraint("period_type IN ('day', 'week', 'month', 'year')", name=f"ck_{table}_period_type"),
        sa.CheckConstraint("currency_code ~ '^[A-Z]{3}$'", name=f"ck_{table}_currency_code"),
        sa.CheckConstraint("currency_exponent BETWEEN 0 AND 6", name=f"ck_{table}_currency_exponent"),
    ]
    if category:
        constraints.extend(
            [
                sa.UniqueConstraint("user_id", "category_id", name="uq_budgets_user_category"),
                sa.ForeignKeyConstraint(
                    ["user_id", "category_id"],
                    ["categories.user_id", "categories.id"],
                    name="fk_budgets_category_owner",
                    ondelete="RESTRICT",
                ),
            ]
        )
    else:
        constraints.append(sa.UniqueConstraint("user_id", name="uq_main_budgets_user_id"))
    op.create_table(table, *columns, *constraints)
    op.create_index(f"ix_{table}_user_id", table, ["user_id"])


def upgrade() -> None:
    _columns("main_budgets")
    _columns("budgets", category=True)
    op.create_index("ix_budgets_category_id", "budgets", ["category_id"])


def downgrade() -> None:
    op.drop_table("budgets")
    op.drop_table("main_budgets")
