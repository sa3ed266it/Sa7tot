"""add remote recurrence foundation

Revision ID: 0003_recurrence_foundation
Revises: 0002_budget_remote
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0003_recurrence_foundation"
down_revision: str | None = "0002_budget_remote"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    timestamp = sa.DateTime(timezone=True)
    uuid_type = sa.UUID(as_uuid=True)

    op.create_table(
        "recurrence_rules",
        sa.Column("id", uuid_type, primary_key=True),
        sa.Column("user_id", uuid_type, nullable=False),
        sa.Column("account_id", uuid_type, nullable=False),
        sa.Column("category_id", uuid_type, nullable=True),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("amount_minor", sa.BigInteger(), nullable=False),
        sa.Column("currency_code", sa.String(length=3), nullable=False),
        sa.Column("currency_exponent", sa.SmallInteger(), nullable=False, server_default="2"),
        sa.Column("title", sa.Text(), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("merchant", sa.Text(), nullable=True),
        sa.Column("cadence", sa.Text(), nullable=False),
        sa.Column("cadence_interval", sa.SmallInteger(), nullable=False, server_default="1"),
        sa.Column("anchor_date", sa.Date(), nullable=False),
        sa.Column("next_occurrence_date", sa.Date(), nullable=False),
        sa.Column("status", sa.Text(), nullable=False, server_default="active"),
        sa.Column("created_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "id", name="uq_recurrence_rules_user_id_id"),
        sa.ForeignKeyConstraint(
            ["user_id", "account_id"],
            ["accounts.user_id", "accounts.id"],
            name="fk_recurrence_rules_account_owner",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["user_id", "category_id"],
            ["categories.user_id", "categories.id"],
            name="fk_recurrence_rules_category_owner",
            ondelete="RESTRICT",
        ),
        sa.CheckConstraint("kind IN ('expense', 'income')", name="ck_recurrence_rules_kind"),
        sa.CheckConstraint("amount_minor > 0", name="ck_recurrence_rules_amount_positive"),
        sa.CheckConstraint("currency_code ~ '^[A-Z]{3}$'", name="ck_recurrence_rules_currency_code"),
        sa.CheckConstraint("currency_exponent BETWEEN 0 AND 6", name="ck_recurrence_rules_currency_exponent"),
        sa.CheckConstraint("cadence IN ('daily', 'weekly', 'monthly')", name="ck_recurrence_rules_cadence"),
        sa.CheckConstraint("cadence_interval > 0", name="ck_recurrence_rules_interval_positive"),
        sa.CheckConstraint("status IN ('active', 'paused', 'cancelled')", name="ck_recurrence_rules_status"),
    )
    op.create_index(
        "ix_recurrence_rules_user_status_next",
        "recurrence_rules",
        ["user_id", "status", "next_occurrence_date"],
    )
    op.create_index("ix_recurrence_rules_account", "recurrence_rules", ["account_id", "next_occurrence_date"])

    op.create_table(
        "recurrence_occurrences",
        sa.Column("id", uuid_type, primary_key=True),
        sa.Column("user_id", uuid_type, nullable=False),
        sa.Column("rule_id", uuid_type, nullable=False),
        sa.Column("scheduled_date", sa.Date(), nullable=False),
        sa.Column("transaction_id", uuid_type, nullable=True),
        sa.Column("materialized_at", timestamp, nullable=True),
        sa.Column("created_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(
            ["user_id", "rule_id"],
            ["recurrence_rules.user_id", "recurrence_rules.id"],
            name="fk_recurrence_occurrences_rule_owner",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["transaction_id"],
            ["transactions.id"],
            name="fk_recurrence_occurrences_transaction",
            ondelete="SET NULL",
        ),
        sa.UniqueConstraint("rule_id", "scheduled_date", name="uq_recurrence_occurrences_rule_date"),
        sa.UniqueConstraint("transaction_id", name="uq_recurrence_occurrences_transaction"),
    )
    op.create_index(
        "ix_recurrence_occurrences_user_scheduled",
        "recurrence_occurrences",
        ["user_id", "scheduled_date"],
    )
    op.create_index(
        "ix_recurrence_occurrences_rule_scheduled",
        "recurrence_occurrences",
        ["rule_id", "scheduled_date"],
    )

    op.add_column("transactions", sa.Column("recurrence_rule_id", uuid_type, nullable=True))
    op.create_foreign_key(
        "fk_transactions_recurrence_rule",
        "transactions",
        "recurrence_rules",
        ["recurrence_rule_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_transactions_recurrence_occurred",
        "transactions",
        ["recurrence_rule_id", "occurred_at", "id"],
    )

    for table_name in ("recurrence_rules", "recurrence_occurrences"):
        op.execute(f"ALTER TABLE {table_name} ENABLE ROW LEVEL SECURITY")
        op.execute(
            f"CREATE POLICY {table_name}_owner_all ON {table_name} "
            "FOR ALL USING (user_id = public.sa7tot_current_user_id()) "
            "WITH CHECK (user_id = public.sa7tot_current_user_id())"
        )
        op.execute(
            f"CREATE TRIGGER {table_name}_updated_at BEFORE UPDATE ON {table_name} "
            "FOR EACH ROW EXECUTE FUNCTION public.sa7tot_touch_updated_at()"
        )


def downgrade() -> None:
    for table_name in ("recurrence_occurrences", "recurrence_rules"):
        op.execute(f"DROP POLICY IF EXISTS {table_name}_owner_all ON {table_name}")
        op.execute(f"DROP TRIGGER IF EXISTS {table_name}_updated_at ON {table_name}")

    op.drop_index("ix_transactions_recurrence_occurred", table_name="transactions")
    op.drop_constraint("fk_transactions_recurrence_rule", "transactions", type_="foreignkey")
    op.drop_column("transactions", "recurrence_rule_id")
    op.drop_index("ix_recurrence_occurrences_rule_scheduled", table_name="recurrence_occurrences")
    op.drop_index("ix_recurrence_occurrences_user_scheduled", table_name="recurrence_occurrences")
    op.drop_table("recurrence_occurrences")
    op.drop_index("ix_recurrence_rules_account", table_name="recurrence_rules")
    op.drop_index("ix_recurrence_rules_user_status_next", table_name="recurrence_rules")
    op.drop_table("recurrence_rules")
