"""add authenticated APNs device token storage

Revision ID: 0007_push_device_tokens
Revises: 0006_financial_calendar
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0007_push_device_tokens"
down_revision: str | None = "0006_financial_calendar"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "push_device_tokens",
        sa.Column("id", UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), nullable=False),
        sa.Column("token", sa.Text(), nullable=False),
        sa.Column("platform", sa.Text(), server_default="ios", nullable=False),
        sa.Column("environment", sa.Text(), nullable=False),
        sa.Column("app_version", sa.Text(), nullable=True),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("platform = 'ios'", name="ck_push_device_tokens_platform_ios"),
        sa.CheckConstraint(
            "environment IN ('development', 'production')",
            name="ck_push_device_tokens_environment",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token", name="uq_push_device_tokens_token"),
    )
    op.create_index(
        "ix_push_device_tokens_user_active",
        "push_device_tokens",
        ["user_id", "is_active"],
    )
    op.execute("ALTER TABLE public.push_device_tokens ENABLE ROW LEVEL SECURITY")
    op.execute(
        "CREATE POLICY push_device_tokens_owner_all ON public.push_device_tokens "
        "FOR ALL USING (user_id = public.sa7tot_current_user_id()) "
        "WITH CHECK (user_id = public.sa7tot_current_user_id())"
    )


def downgrade() -> None:
    op.execute("DROP POLICY IF EXISTS push_device_tokens_owner_all ON public.push_device_tokens")
    op.drop_index("ix_push_device_tokens_user_active", table_name="push_device_tokens")
    op.drop_table("push_device_tokens")
