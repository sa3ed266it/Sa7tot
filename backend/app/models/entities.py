from __future__ import annotations

import uuid
from datetime import UTC, date, datetime

from sqlalchemy import (
    UUID,
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    ForeignKeyConstraint,
    Index,
    Integer,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def utc_now() -> datetime:
    return datetime.now(UTC)


class Base(DeclarativeBase):
    pass


class Timestamped:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=utc_now
    )


class Profile(Timestamped, Base):
    __tablename__ = "profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    locale: Mapped[str | None] = mapped_column(Text, nullable=True)
    timezone: Mapped[str] = mapped_column(Text, nullable=False, default="Europe/Rome", server_default="Europe/Rome")
    default_currency_code: Mapped[str] = mapped_column(String(3), nullable=False, default="EUR", server_default="EUR")
    month_start_day: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=1, server_default="1")
    week_start_day: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=1, server_default="1")


class PushDeviceToken(Timestamped, Base):
    __tablename__ = "push_device_tokens"
    __table_args__ = (
        UniqueConstraint("token", name="uq_push_device_tokens_token"),
        Index("ix_push_device_tokens_user_active", "user_id", "is_active"),
        CheckConstraint("platform = 'ios'", name="ck_push_device_tokens_platform_ios"),
        CheckConstraint(
            "environment IN ('development', 'production')",
            name="ck_push_device_tokens_environment",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    token: Mapped[str] = mapped_column(Text, nullable=False)
    platform: Mapped[str] = mapped_column(Text, nullable=False, default="ios", server_default="ios")
    environment: Mapped[str] = mapped_column(Text, nullable=False)
    app_version: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")


class Account(Timestamped, Base):
    __tablename__ = "accounts"
    __table_args__ = (
        UniqueConstraint("user_id", "id", name="uq_accounts_user_id_id"),
        Index("ix_accounts_user_id", "user_id"),
        Index("ix_accounts_user_archived", "user_id", "is_archived"),
        Index("ix_accounts_user_sort", "user_id", "sort_order"),
        CheckConstraint("currency_code ~ '^[A-Z]{3}$'", name="ck_accounts_currency_code"),
        CheckConstraint("currency_exponent >= 0 AND currency_exponent <= 6", name="ck_accounts_currency_exponent"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    type: Mapped[str] = mapped_column(Text, nullable=False, default="other", server_default="other")
    currency_code: Mapped[str] = mapped_column(String(3), nullable=False)
    currency_exponent: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=2, server_default="2")
    opening_balance_minor: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0, server_default="0")
    icon_name: Mapped[str] = mapped_column(
        Text, nullable=False, default="building.columns.fill", server_default="building.columns.fill"
    )
    color: Mapped[str] = mapped_column(Text, nullable=False, default="#5E7CE2", server_default="#5E7CE2")
    wallet_label: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_archived: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")


class Category(Timestamped, Base):
    __tablename__ = "categories"
    __table_args__ = (
        UniqueConstraint("user_id", "id", name="uq_categories_user_id_id"),
        Index(
            "uq_categories_active_name",
            "user_id",
            "income",
            "normalized_name",
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index(
            "uq_categories_user_preset",
            "user_id",
            "preset_key",
            unique=True,
            postgresql_where=text("preset_key IS NOT NULL"),
        ),
        Index("ix_categories_user_id", "user_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    normalized_name: Mapped[str] = mapped_column(Text, nullable=False)
    income: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    icon_identifier: Mapped[str] = mapped_column(
        Text, nullable=False, default="sf:tag.fill", server_default="sf:tag.fill"
    )
    color: Mapped[str] = mapped_column(Text, nullable=False, default="#FFFFFF", server_default="#FFFFFF")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    preset_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class MainBudget(Timestamped, Base):
    __tablename__ = "main_budgets"
    __table_args__ = (
        UniqueConstraint("user_id", name="uq_main_budgets_user_id"),
        Index("ix_main_budgets_user_id", "user_id"),
        CheckConstraint("amount_minor >= 0", name="ck_main_budgets_amount_nonnegative"),
        CheckConstraint("period_type IN ('day', 'week', 'month', 'year')", name="ck_main_budgets_period_type"),
        CheckConstraint("currency_code ~ '^[A-Z]{3}$'", name="ck_main_budgets_currency_code"),
        CheckConstraint("currency_exponent BETWEEN 0 AND 6", name="ck_main_budgets_currency_exponent"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    amount_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency_code: Mapped[str] = mapped_column(String(3), nullable=False)
    currency_exponent: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=2, server_default="2")
    period_type: Mapped[str] = mapped_column(Text, nullable=False)
    period_start: Mapped[date] = mapped_column(Date, nullable=False)


class Budget(Timestamped, Base):
    __tablename__ = "budgets"
    __table_args__ = (
        UniqueConstraint("user_id", "category_id", name="uq_budgets_user_category"),
        ForeignKeyConstraint(
            ["user_id", "category_id"],
            ["categories.user_id", "categories.id"],
            name="fk_budgets_category_owner",
            ondelete="RESTRICT",
        ),
        Index("ix_budgets_user_id", "user_id"),
        Index("ix_budgets_category_id", "category_id"),
        CheckConstraint("amount_minor >= 0", name="ck_budgets_amount_nonnegative"),
        CheckConstraint("period_type IN ('day', 'week', 'month', 'year')", name="ck_budgets_period_type"),
        CheckConstraint("currency_code ~ '^[A-Z]{3}$'", name="ck_budgets_currency_code"),
        CheckConstraint("currency_exponent BETWEEN 0 AND 6", name="ck_budgets_currency_exponent"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    category_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    amount_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency_code: Mapped[str] = mapped_column(String(3), nullable=False)
    currency_exponent: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=2, server_default="2")
    period_type: Mapped[str] = mapped_column(Text, nullable=False)
    period_start: Mapped[date] = mapped_column(Date, nullable=False)


class Subscription(Timestamped, Base):
    __tablename__ = "subscriptions"
    __table_args__ = (
        UniqueConstraint("user_id", "id", name="uq_subscriptions_user_id_id"),
        ForeignKeyConstraint(
            ["user_id", "account_id"],
            ["accounts.user_id", "accounts.id"],
            name="fk_subscriptions_account_owner",
            ondelete="RESTRICT",
        ),
        ForeignKeyConstraint(
            ["user_id", "category_id"],
            ["categories.user_id", "categories.id"],
            name="fk_subscriptions_category_owner",
            ondelete="RESTRICT",
        ),
        Index("ix_subscriptions_user_next_date", "user_id", "next_billing_date"),
        CheckConstraint("amount_minor > 0", name="ck_subscriptions_amount_positive"),
        CheckConstraint("cadence_interval > 0", name="ck_subscriptions_interval_positive"),
        CheckConstraint("cadence IN ('weekly', 'monthly', 'yearly')", name="ck_subscriptions_cadence"),
        CheckConstraint("status IN ('active', 'paused', 'cancelled')", name="ck_subscriptions_status"),
        CheckConstraint(
            "(service_id IS NOT NULL AND custom_name IS NULL) OR (service_id IS NULL AND custom_name IS NOT NULL)",
            name="ck_subscriptions_identity",
        ),
        CheckConstraint("currency_code ~ '^[A-Z]{3}$'", name="ck_subscriptions_currency_code"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    account_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    category_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    service_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    custom_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    amount_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency_code: Mapped[str] = mapped_column(String(3), nullable=False)
    currency_exponent: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    cadence: Mapped[str] = mapped_column(Text, nullable=False)
    cadence_interval: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=1, server_default="1")
    billing_anchor: Mapped[date] = mapped_column(Date, nullable=False)
    next_billing_date: Mapped[date] = mapped_column(Date, nullable=False)
    schedule_changed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[str] = mapped_column(Text, nullable=False, default="active", server_default="active")
    note: Mapped[str | None] = mapped_column(Text, nullable=True)


class SubscriptionReminderDelivery(Timestamped, Base):
    __tablename__ = "subscription_reminder_deliveries"
    __table_args__ = (
        UniqueConstraint("user_id", "id", name="uq_subscription_reminder_deliveries_user_id_id"),
        UniqueConstraint(
            "user_id",
            "subscription_id",
            "renewal_date",
            "reminder_type",
            "lead_days",
            name="uq_subscription_reminder_deliveries_identity",
        ),
        ForeignKeyConstraint(
            ["user_id", "subscription_id"],
            ["subscriptions.user_id", "subscriptions.id"],
            name="fk_subscription_reminder_deliveries_subscription_owner",
            ondelete="RESTRICT",
        ),
        Index("ix_subscription_reminder_deliveries_status_renewal", "status", "renewal_date"),
        Index("ix_subscription_reminder_deliveries_user_subscription", "user_id", "subscription_id"),
        CheckConstraint(
            "status IN ('pending', 'sending', 'completed', 'cancelled', 'expired')",
            name="ck_subscription_reminder_deliveries_status",
        ),
        CheckConstraint("lead_days > 0", name="ck_subscription_reminder_deliveries_lead_days_positive"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    subscription_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    renewal_date: Mapped[date] = mapped_column(Date, nullable=False)
    reminder_type: Mapped[str] = mapped_column(Text, nullable=False, default="subscription_renewal")
    lead_days: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=7, server_default="7")
    status: Mapped[str] = mapped_column(Text, nullable=False, default="pending", server_default="pending")
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class SubscriptionReminderDeviceDelivery(Timestamped, Base):
    __tablename__ = "subscription_reminder_device_deliveries"
    __table_args__ = (
        UniqueConstraint("user_id", "id", name="uq_subscription_reminder_device_deliveries_user_id_id"),
        UniqueConstraint(
            "reminder_delivery_id",
            "push_device_token_id",
            name="uq_subscription_reminder_device_deliveries_identity",
        ),
        ForeignKeyConstraint(
            ["user_id", "reminder_delivery_id"],
            ["subscription_reminder_deliveries.user_id", "subscription_reminder_deliveries.id"],
            name="fk_subscription_reminder_device_deliveries_reminder_owner",
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["push_device_token_id"],
            ["push_device_tokens.id"],
            name="fk_subscription_reminder_device_deliveries_device",
            ondelete="RESTRICT",
        ),
        Index("ix_subscription_reminder_device_deliveries_status_retry", "status", "next_attempt_at"),
        Index("ix_subscription_reminder_device_deliveries_user_id", "user_id"),
        CheckConstraint(
            "status IN ('pending', 'sending', 'sent', 'retryable', 'permanent_failure', 'expired')",
            name="ck_subscription_reminder_device_deliveries_status",
        ),
        CheckConstraint("attempt_count >= 0", name="ck_subscription_reminder_device_deliveries_attempts_nonnegative"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    reminder_delivery_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    push_device_token_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False, default="pending", server_default="pending")
    attempt_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    last_attempt_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    next_attempt_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    apns_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_error_kind: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_error_reason: Mapped[str | None] = mapped_column(Text, nullable=True)


class RecurrenceRule(Timestamped, Base):
    __tablename__ = "recurrence_rules"
    __table_args__ = (
        UniqueConstraint("user_id", "id", name="uq_recurrence_rules_user_id_id"),
        ForeignKeyConstraint(
            ["user_id", "account_id"],
            ["accounts.user_id", "accounts.id"],
            name="fk_recurrence_rules_account_owner",
            ondelete="RESTRICT",
        ),
        ForeignKeyConstraint(
            ["user_id", "category_id"],
            ["categories.user_id", "categories.id"],
            name="fk_recurrence_rules_category_owner",
            ondelete="RESTRICT",
        ),
        Index("ix_recurrence_rules_user_status_next", "user_id", "status", "next_occurrence_date"),
        Index("ix_recurrence_rules_account", "account_id", "next_occurrence_date"),
        CheckConstraint("kind IN ('expense', 'income')", name="ck_recurrence_rules_kind"),
        CheckConstraint("amount_minor > 0", name="ck_recurrence_rules_amount_positive"),
        CheckConstraint("currency_code ~ '^[A-Z]{3}$'", name="ck_recurrence_rules_currency_code"),
        CheckConstraint("currency_exponent BETWEEN 0 AND 6", name="ck_recurrence_rules_currency_exponent"),
        CheckConstraint("cadence IN ('daily', 'weekly', 'monthly')", name="ck_recurrence_rules_cadence"),
        CheckConstraint("cadence_interval > 0", name="ck_recurrence_rules_interval_positive"),
        CheckConstraint("status IN ('active', 'paused', 'cancelled')", name="ck_recurrence_rules_status"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    account_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    category_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    amount_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency_code: Mapped[str] = mapped_column(String(3), nullable=False)
    currency_exponent: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=2, server_default="2")
    title: Mapped[str | None] = mapped_column(Text, nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    merchant: Mapped[str | None] = mapped_column(Text, nullable=True)
    cadence: Mapped[str] = mapped_column(Text, nullable=False)
    cadence_interval: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=1, server_default="1")
    anchor_date: Mapped[date] = mapped_column(Date, nullable=False)
    next_occurrence_date: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False, default="active", server_default="active")


class Transaction(Timestamped, Base):
    __tablename__ = "transactions"
    __table_args__ = (
        UniqueConstraint("user_id", "id", name="uq_transactions_user_id_id"),
        ForeignKeyConstraint(
            ["user_id", "account_id"],
            ["accounts.user_id", "accounts.id"],
            name="fk_transactions_account_owner",
            ondelete="RESTRICT",
        ),
        ForeignKeyConstraint(
            ["user_id", "destination_account_id"],
            ["accounts.user_id", "accounts.id"],
            name="fk_transactions_destination_owner",
            ondelete="RESTRICT",
        ),
        Index("ix_transactions_user_occurred", "user_id", "occurred_at", "id"),
        Index("ix_transactions_account_occurred", "account_id", "occurred_at", "id"),
        Index("ix_transactions_destination_occurred", "destination_account_id", "occurred_at", "id"),
        Index("ix_transactions_category_occurred", "category_id", "occurred_at", "id"),
        Index("ix_transactions_subscription_occurred", "subscription_id", "occurred_at", "id"),
        Index("ix_transactions_recurrence_occurred", "recurrence_rule_id", "occurred_at", "id"),
        CheckConstraint("amount_minor > 0", name="ck_transactions_amount_positive"),
        CheckConstraint("currency_code ~ '^[A-Z]{3}$'", name="ck_transactions_currency_code"),
        CheckConstraint("kind IN ('expense', 'income', 'transfer')", name="ck_transactions_kind"),
        CheckConstraint(
            "(kind IN ('expense', 'income') AND destination_account_id IS NULL) OR "
            "(kind = 'transfer' AND destination_account_id IS NOT NULL AND account_id <> destination_account_id)",
            name="ck_transactions_kind_accounts",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    account_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    destination_account_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    amount_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency_code: Mapped[str] = mapped_column(String(3), nullable=False)
    currency_exponent: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    local_day: Mapped[date] = mapped_column(Date, nullable=False)
    category_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("categories.id", ondelete="SET NULL"), nullable=True
    )
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    merchant: Mapped[str | None] = mapped_column(Text, nullable=True)
    normalized_merchant: Mapped[str | None] = mapped_column(Text, nullable=True)
    origin: Mapped[str | None] = mapped_column(Text, nullable=True)
    review_status: Mapped[str | None] = mapped_column(Text, nullable=True)
    external_reference: Mapped[str | None] = mapped_column(Text, nullable=True)
    recurrence_rule_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("recurrence_rules.id", ondelete="SET NULL"), nullable=True
    )
    subscription_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("subscriptions.id", ondelete="SET NULL"), nullable=True
    )
    subscription_service_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    subscription_occurrence_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    subscription_display_name: Mapped[str | None] = mapped_column(Text, nullable=True)


class RecurrenceOccurrence(Timestamped, Base):
    __tablename__ = "recurrence_occurrences"
    __table_args__ = (
        ForeignKeyConstraint(
            ["user_id", "rule_id"],
            ["recurrence_rules.user_id", "recurrence_rules.id"],
            name="fk_recurrence_occurrences_rule_owner",
            ondelete="CASCADE",
        ),
        Index("ix_recurrence_occurrences_user_scheduled", "user_id", "scheduled_date"),
        Index("ix_recurrence_occurrences_rule_scheduled", "rule_id", "scheduled_date"),
        UniqueConstraint("rule_id", "scheduled_date", name="uq_recurrence_occurrences_rule_date"),
        UniqueConstraint("transaction_id", name="uq_recurrence_occurrences_transaction"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    rule_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    scheduled_date: Mapped[date] = mapped_column(Date, nullable=False)
    transaction_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("transactions.id", ondelete="SET NULL"), nullable=True
    )
    materialized_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class SubscriptionOccurrence(Timestamped, Base):
    __tablename__ = "subscription_occurrences"
    __table_args__ = (
        ForeignKeyConstraint(
            ["user_id", "subscription_id"],
            ["subscriptions.user_id", "subscriptions.id"],
            name="fk_occurrences_subscription_owner",
            ondelete="CASCADE",
        ),
        Index("ix_occurrences_user_scheduled", "user_id", "scheduled_date"),
        UniqueConstraint("subscription_id", "occurrence_key", name="uq_subscription_occurrence_key"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    subscription_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    occurrence_key: Mapped[str] = mapped_column(Text, nullable=False)
    scheduled_date: Mapped[date] = mapped_column(Date, nullable=False)
    transaction_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("transactions.id", ondelete="SET NULL"), nullable=True
    )
    materialized_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
