"""create clean remote foundation

Revision ID: 0001_backend_foundation
Revises:
Create Date: 2026-08-08
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0001_backend_foundation"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    timestamp = sa.DateTime(timezone=True)
    uuid_type = sa.UUID(as_uuid=True)

    op.create_table(
        "profiles",
        sa.Column("user_id", uuid_type, primary_key=True),
        sa.Column("locale", sa.Text(), nullable=True),
        sa.Column("timezone", sa.Text(), nullable=False, server_default="Europe/Rome"),
        sa.Column("default_currency_code", sa.String(length=3), nullable=False, server_default="EUR"),
        sa.Column("created_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", timestamp, nullable=False, server_default=sa.func.now()),
    )

    op.create_table(
        "accounts",
        sa.Column("id", uuid_type, primary_key=True),
        sa.Column("user_id", uuid_type, nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("type", sa.Text(), nullable=False, server_default="other"),
        sa.Column("currency_code", sa.String(length=3), nullable=False),
        sa.Column("currency_exponent", sa.SmallInteger(), nullable=False, server_default="2"),
        sa.Column("opening_balance_minor", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("icon_name", sa.Text(), nullable=False, server_default="building.columns.fill"),
        sa.Column("color", sa.Text(), nullable=False, server_default="#5E7CE2"),
        sa.Column("wallet_label", sa.Text(), nullable=True),
        sa.Column("is_archived", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "id", name="uq_accounts_user_id_id"),
        sa.CheckConstraint("currency_code ~ '^[A-Z]{3}$'", name="ck_accounts_currency_code"),
        sa.CheckConstraint("currency_exponent BETWEEN 0 AND 6", name="ck_accounts_currency_exponent"),
    )
    op.create_index("ix_accounts_user_id", "accounts", ["user_id"])
    op.create_index("ix_accounts_user_archived", "accounts", ["user_id", "is_archived"])
    op.create_index("ix_accounts_user_sort", "accounts", ["user_id", "sort_order"])

    op.create_table(
        "categories",
        sa.Column("id", uuid_type, primary_key=True),
        sa.Column("user_id", uuid_type, nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("normalized_name", sa.Text(), nullable=False),
        sa.Column("income", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("icon_identifier", sa.Text(), nullable=False, server_default="sf:tag.fill"),
        sa.Column("color", sa.Text(), nullable=False, server_default="#FFFFFF"),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("deleted_at", timestamp, nullable=True),
        sa.Column("created_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "id", name="uq_categories_user_id_id"),
    )
    op.create_index("ix_categories_user_id", "categories", ["user_id"])
    op.create_index(
        "uq_categories_active_name",
        "categories",
        ["user_id", "income", "normalized_name"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )

    op.create_table(
        "subscriptions",
        sa.Column("id", uuid_type, primary_key=True),
        sa.Column("user_id", uuid_type, nullable=False),
        sa.Column("account_id", uuid_type, nullable=False),
        sa.Column("category_id", uuid_type, nullable=True),
        sa.Column("service_id", sa.Text(), nullable=True),
        sa.Column("custom_name", sa.Text(), nullable=True),
        sa.Column("amount_minor", sa.BigInteger(), nullable=False),
        sa.Column("currency_code", sa.String(length=3), nullable=False),
        sa.Column("currency_exponent", sa.SmallInteger(), nullable=False),
        sa.Column("cadence", sa.Text(), nullable=False),
        sa.Column("cadence_interval", sa.SmallInteger(), nullable=False, server_default="1"),
        sa.Column("billing_anchor", sa.Date(), nullable=False),
        sa.Column("next_billing_date", sa.Date(), nullable=False),
        sa.Column("status", sa.Text(), nullable=False, server_default="active"),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("created_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "id", name="uq_subscriptions_user_id_id"),
        sa.ForeignKeyConstraint(
            ["user_id", "account_id"],
            ["accounts.user_id", "accounts.id"],
            name="fk_subscriptions_account_owner",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["user_id", "category_id"],
            ["categories.user_id", "categories.id"],
            name="fk_subscriptions_category_owner",
            ondelete="RESTRICT",
        ),
        sa.CheckConstraint("amount_minor > 0", name="ck_subscriptions_amount_positive"),
        sa.CheckConstraint("cadence_interval > 0", name="ck_subscriptions_interval_positive"),
        sa.CheckConstraint("cadence IN ('weekly', 'monthly', 'yearly')", name="ck_subscriptions_cadence"),
        sa.CheckConstraint("status IN ('active', 'paused', 'cancelled')", name="ck_subscriptions_status"),
        sa.CheckConstraint("currency_code ~ '^[A-Z]{3}$'", name="ck_subscriptions_currency_code"),
        sa.CheckConstraint(
            "(service_id IS NOT NULL AND custom_name IS NULL) OR (service_id IS NULL AND custom_name IS NOT NULL)",
            name="ck_subscriptions_identity",
        ),
    )
    op.create_index("ix_subscriptions_user_next_date", "subscriptions", ["user_id", "next_billing_date"])

    op.create_table(
        "transactions",
        sa.Column("id", uuid_type, primary_key=True),
        sa.Column("user_id", uuid_type, nullable=False),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("account_id", uuid_type, nullable=False),
        sa.Column("destination_account_id", uuid_type, nullable=True),
        sa.Column("amount_minor", sa.BigInteger(), nullable=False),
        sa.Column("currency_code", sa.String(length=3), nullable=False),
        sa.Column("currency_exponent", sa.SmallInteger(), nullable=False),
        sa.Column("occurred_at", timestamp, nullable=False),
        sa.Column("local_day", sa.Date(), nullable=False),
        sa.Column(
            "category_id",
            uuid_type,
            sa.ForeignKey("categories.id", name="fk_transactions_category", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("merchant", sa.Text(), nullable=True),
        sa.Column("normalized_merchant", sa.Text(), nullable=True),
        sa.Column("origin", sa.Text(), nullable=True),
        sa.Column("review_status", sa.Text(), nullable=True),
        sa.Column("external_reference", sa.Text(), nullable=True),
        sa.Column(
            "subscription_id",
            uuid_type,
            sa.ForeignKey("subscriptions.id", name="fk_transactions_subscription", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("subscription_service_id", sa.Text(), nullable=True),
        sa.Column("subscription_occurrence_key", sa.Text(), nullable=True),
        sa.Column("subscription_display_name", sa.Text(), nullable=True),
        sa.Column("created_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "id", name="uq_transactions_user_id_id"),
        sa.ForeignKeyConstraint(
            ["user_id", "account_id"],
            ["accounts.user_id", "accounts.id"],
            name="fk_transactions_account_owner",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["user_id", "destination_account_id"],
            ["accounts.user_id", "accounts.id"],
            name="fk_transactions_destination_owner",
            ondelete="RESTRICT",
        ),
        sa.CheckConstraint("kind IN ('expense', 'income', 'transfer')", name="ck_transactions_kind"),
        sa.CheckConstraint("amount_minor > 0", name="ck_transactions_amount_positive"),
        sa.CheckConstraint("currency_code ~ '^[A-Z]{3}$'", name="ck_transactions_currency_code"),
        sa.CheckConstraint(
            "(kind IN ('expense', 'income') AND destination_account_id IS NULL) OR "
            "(kind = 'transfer' AND destination_account_id IS NOT NULL AND account_id <> destination_account_id)",
            name="ck_transactions_kind_accounts",
        ),
    )
    op.create_index("ix_transactions_user_occurred", "transactions", ["user_id", "occurred_at", "id"])
    op.create_index("ix_transactions_account_occurred", "transactions", ["account_id", "occurred_at", "id"])
    op.create_index(
        "ix_transactions_destination_occurred",
        "transactions",
        ["destination_account_id", "occurred_at", "id"],
    )
    op.create_index("ix_transactions_category_occurred", "transactions", ["category_id", "occurred_at", "id"])
    op.create_index(
        "ix_transactions_subscription_occurred",
        "transactions",
        ["subscription_id", "occurred_at", "id"],
    )

    op.create_table(
        "subscription_occurrences",
        sa.Column("id", uuid_type, primary_key=True),
        sa.Column("user_id", uuid_type, nullable=False),
        sa.Column("subscription_id", uuid_type, nullable=False),
        sa.Column("occurrence_key", sa.Text(), nullable=False),
        sa.Column("scheduled_date", sa.Date(), nullable=False),
        sa.Column(
            "transaction_id",
            uuid_type,
            sa.ForeignKey("transactions.id", name="fk_occurrences_transaction", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("materialized_at", timestamp, nullable=True),
        sa.Column("created_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", timestamp, nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("subscription_id", "occurrence_key", name="uq_subscription_occurrence_key"),
        sa.ForeignKeyConstraint(
            ["user_id", "subscription_id"],
            ["subscriptions.user_id", "subscriptions.id"],
            name="fk_occurrences_subscription_owner",
            ondelete="CASCADE",
        ),
    )
    op.create_index("ix_occurrences_user_scheduled", "subscription_occurrences", ["user_id", "scheduled_date"])

    op.execute(
        """
        CREATE OR REPLACE FUNCTION public.sa7tot_current_user_id() RETURNS uuid
        LANGUAGE sql STABLE SECURITY DEFINER AS $$
          SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
        $$;
        """
    )
    for table_name in (
        "profiles",
        "accounts",
        "categories",
        "subscriptions",
        "transactions",
        "subscription_occurrences",
    ):
        op.execute(f"ALTER TABLE {table_name} ENABLE ROW LEVEL SECURITY")
        op.execute(
            f"CREATE POLICY {table_name}_owner_all ON {table_name} "
            "FOR ALL USING (user_id = public.sa7tot_current_user_id()) "
            "WITH CHECK (user_id = public.sa7tot_current_user_id())"
        )

    op.execute(
        """
        CREATE OR REPLACE FUNCTION public.sa7tot_touch_updated_at() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
          NEW.updated_at = now();
          RETURN NEW;
        END;
        $$;
        """
    )
    for table_name in (
        "profiles",
        "accounts",
        "categories",
        "subscriptions",
        "transactions",
        "subscription_occurrences",
    ):
        op.execute(
            f"CREATE TRIGGER {table_name}_updated_at BEFORE UPDATE ON {table_name} "
            "FOR EACH ROW EXECUTE FUNCTION public.sa7tot_touch_updated_at()"
        )


def downgrade() -> None:
    for table_name in (
        "subscription_occurrences",
        "transactions",
        "subscriptions",
        "categories",
        "accounts",
        "profiles",
    ):
        op.execute(f"DROP POLICY IF EXISTS {table_name}_owner_all ON {table_name}")
        op.execute(f"DROP TRIGGER IF EXISTS {table_name}_updated_at ON {table_name}")
    op.drop_table("subscription_occurrences")
    op.drop_table("transactions")
    op.drop_table("subscriptions")
    op.drop_index("uq_categories_active_name", table_name="categories")
    op.drop_table("categories")
    op.drop_index("ix_accounts_user_sort", table_name="accounts")
    op.drop_index("ix_accounts_user_archived", table_name="accounts")
    op.drop_index("ix_accounts_user_id", table_name="accounts")
    op.drop_table("accounts")
    op.drop_table("profiles")
    op.execute("DROP FUNCTION IF EXISTS public.sa7tot_touch_updated_at()")
    op.execute("DROP FUNCTION IF EXISTS public.sa7tot_current_user_id()")
