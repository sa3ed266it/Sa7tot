"""harden budget RLS and Alembic metadata access

Revision ID: 0004_rls_hardening
Revises: 0003_recurrence_foundation
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0004_rls_hardening"
down_revision: str | None = "0003_recurrence_foundation"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


_BUDGET_TABLES = ("budgets", "main_budgets")


def _install_owner_policy(table_name: str) -> None:
    op.execute(f"ALTER TABLE public.{table_name} ENABLE ROW LEVEL SECURITY")
    op.execute(f"DROP POLICY IF EXISTS {table_name}_owner_all ON public.{table_name}")
    op.execute(
        f"CREATE POLICY {table_name}_owner_all ON public.{table_name} "
        "FOR ALL USING (user_id = public.sa7tot_current_user_id()) "
        "WITH CHECK (user_id = public.sa7tot_current_user_id())"
    )


def upgrade() -> None:
    for table_name in _BUDGET_TABLES:
        _install_owner_policy(table_name)

    # alembic_version is system metadata, not user data. Keep the database
    # owner/Alembic role and service_role access intact, while removing normal
    # Supabase API-role access. The conditional grants handle local PostgreSQL
    # installations that do not define Supabase's roles.
    op.execute("REVOKE ALL ON TABLE public.alembic_version FROM PUBLIC")
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
                REVOKE ALL ON TABLE public.alembic_version FROM anon;
            END IF;
            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
                REVOKE ALL ON TABLE public.alembic_version FROM authenticated;
            END IF;
        END
        $$;
        """
    )


def downgrade() -> None:
    for table_name in _BUDGET_TABLES:
        op.execute(f"DROP POLICY IF EXISTS {table_name}_owner_all ON public.{table_name}")
        op.execute(f"ALTER TABLE public.{table_name} DISABLE ROW LEVEL SECURITY")

    # Do not restore API-role access to system migration metadata during a
    # downgrade; preserving this hardening is safer than re-exposing it.
    op.execute("REVOKE ALL ON TABLE public.alembic_version FROM PUBLIC")
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
                REVOKE ALL ON TABLE public.alembic_version FROM anon;
            END IF;
            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
                REVOKE ALL ON TABLE public.alembic_version FROM authenticated;
            END IF;
        END
        $$;
        """
    )
