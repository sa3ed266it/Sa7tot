"""add durable subscription reminder delivery state

Revision ID: 0008_subscription_reminders
Revises: 0007_push_device_tokens
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from alembic import op

revision: str = "0008_subscription_reminders"
down_revision: str | None = "0007_push_device_tokens"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "subscriptions",
        sa.Column("schedule_changed_at", sa.DateTime(timezone=True), nullable=True),
    )

    op.create_table(
        "subscription_reminder_deliveries",
        sa.Column("id", UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), nullable=False),
        sa.Column("subscription_id", UUID(as_uuid=True), nullable=False),
        sa.Column("renewal_date", sa.Date(), nullable=False),
        sa.Column("reminder_type", sa.Text(), nullable=False),
        sa.Column("lead_days", sa.SmallInteger(), server_default="7", nullable=False),
        sa.Column("status", sa.Text(), server_default="pending", nullable=False),
        sa.Column("claimed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id", "subscription_id"],
            ["subscriptions.user_id", "subscriptions.id"],
            name="fk_subscription_reminder_deliveries_subscription_owner",
            ondelete="RESTRICT",
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'sending', 'completed', 'cancelled', 'expired')",
            name="ck_subscription_reminder_deliveries_status",
        ),
        sa.CheckConstraint("lead_days > 0", name="ck_subscription_reminder_deliveries_lead_days_positive"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "id", name="uq_subscription_reminder_deliveries_user_id_id"),
        sa.UniqueConstraint(
            "user_id",
            "subscription_id",
            "renewal_date",
            "reminder_type",
            "lead_days",
            name="uq_subscription_reminder_deliveries_identity",
        ),
    )
    op.create_index(
        "ix_subscription_reminder_deliveries_status_renewal",
        "subscription_reminder_deliveries",
        ["status", "renewal_date"],
    )
    op.create_index(
        "ix_subscription_reminder_deliveries_user_subscription",
        "subscription_reminder_deliveries",
        ["user_id", "subscription_id"],
    )

    op.create_table(
        "subscription_reminder_device_deliveries",
        sa.Column("id", UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), nullable=False),
        sa.Column("reminder_delivery_id", UUID(as_uuid=True), nullable=False),
        sa.Column("push_device_token_id", UUID(as_uuid=True), nullable=False),
        sa.Column("status", sa.Text(), server_default="pending", nullable=False),
        sa.Column("attempt_count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("last_attempt_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("apns_id", sa.Text(), nullable=True),
        sa.Column("last_error_kind", sa.Text(), nullable=True),
        sa.Column("last_error_reason", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id", "reminder_delivery_id"],
            ["subscription_reminder_deliveries.user_id", "subscription_reminder_deliveries.id"],
            name="fk_subscription_reminder_device_deliveries_reminder_owner",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["push_device_token_id"],
            ["push_device_tokens.id"],
            name="fk_subscription_reminder_device_deliveries_device",
            ondelete="RESTRICT",
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'sending', 'sent', 'retryable', 'permanent_failure', 'expired')",
            name="ck_subscription_reminder_device_deliveries_status",
        ),
        sa.CheckConstraint(
            "attempt_count >= 0",
            name="ck_subscription_reminder_device_deliveries_attempts_nonnegative",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "id", name="uq_subscription_reminder_device_deliveries_user_id_id"),
        sa.UniqueConstraint(
            "reminder_delivery_id",
            "push_device_token_id",
            name="uq_subscription_reminder_device_deliveries_identity",
        ),
    )
    op.create_index(
        "ix_subscription_reminder_device_deliveries_status_retry",
        "subscription_reminder_device_deliveries",
        ["status", "next_attempt_at"],
    )
    op.create_index(
        "ix_subscription_reminder_device_deliveries_user_id",
        "subscription_reminder_device_deliveries",
        ["user_id"],
    )

    for table_name in ("subscription_reminder_deliveries", "subscription_reminder_device_deliveries"):
        op.execute(f"ALTER TABLE public.{table_name} ENABLE ROW LEVEL SECURITY")
        op.execute(
            f"CREATE POLICY {table_name}_owner_all ON public.{table_name} "
            "FOR ALL USING (user_id = public.sa7tot_current_user_id()) "
            "WITH CHECK (user_id = public.sa7tot_current_user_id())"
        )


def downgrade() -> None:
    for table_name in ("subscription_reminder_device_deliveries", "subscription_reminder_deliveries"):
        op.execute(f"DROP POLICY IF EXISTS {table_name}_owner_all ON public.{table_name}")

    op.drop_index(
        "ix_subscription_reminder_device_deliveries_user_id",
        table_name="subscription_reminder_device_deliveries",
    )
    op.drop_index(
        "ix_subscription_reminder_device_deliveries_status_retry",
        table_name="subscription_reminder_device_deliveries",
    )
    op.drop_table("subscription_reminder_device_deliveries")
    op.drop_index(
        "ix_subscription_reminder_deliveries_user_subscription",
        table_name="subscription_reminder_deliveries",
    )
    op.drop_index(
        "ix_subscription_reminder_deliveries_status_renewal",
        table_name="subscription_reminder_deliveries",
    )
    op.drop_table("subscription_reminder_deliveries")
    op.drop_column("subscriptions", "schedule_changed_at")
