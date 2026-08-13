from __future__ import annotations

import pytest
from sqlalchemy import text

USER_DATA_TABLES = (
    "profiles",
    "accounts",
    "categories",
    "transactions",
    "subscriptions",
    "push_device_tokens",
    "subscription_reminder_deliveries",
    "subscription_reminder_device_deliveries",
    "subscription_occurrences",
    "recurrence_rules",
    "recurrence_occurrences",
    "budgets",
    "main_budgets",
)


@pytest.mark.asyncio
async def test_all_user_data_tables_have_owner_rls(session) -> None:
    table_list = ", ".join(f"'{table}'" for table in USER_DATA_TABLES)
    rows = (
        await session.execute(
            text(
                f"""
                SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity
                FROM pg_class AS c
                JOIN pg_namespace AS n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public' AND c.relname IN ({table_list})
                """
            )
        )
    ).all()

    security = {row.relname: (row.relrowsecurity, row.relforcerowsecurity) for row in rows}
    assert set(security) == set(USER_DATA_TABLES)
    assert all(rls and not forced for rls, forced in security.values())


@pytest.mark.asyncio
async def test_user_data_policies_use_owner_check_and_with_check(session) -> None:
    table_list = ", ".join(f"'{table}'" for table in USER_DATA_TABLES)
    rows = (
        await session.execute(
            text(
                f"""
                SELECT tablename, policyname, cmd, qual::text, with_check::text
                FROM pg_policies
                WHERE schemaname = 'public' AND tablename IN ({table_list})
                ORDER BY tablename
                """
            )
        )
    ).all()

    policies = {row.tablename: row for row in rows}
    assert set(policies) == set(USER_DATA_TABLES)
    for table_name, row in policies.items():
        assert row.policyname == f"{table_name}_owner_all"
        assert row.cmd == "ALL"
        assert "user_id = sa7tot_current_user_id()" in row.qual
        assert "user_id = sa7tot_current_user_id()" in row.with_check


@pytest.mark.asyncio
async def test_alembic_version_has_no_normal_api_role_grants(session) -> None:
    roles = set(
        (
            await session.execute(text("SELECT rolname FROM pg_roles WHERE rolname IN ('anon', 'authenticated')"))
        ).scalars()
    )
    if not roles:
        pytest.skip("Supabase API roles are not present in the local PostgreSQL test database")

    rows = (
        await session.execute(
            text(
                """
                SELECT grantee, privilege_type
                FROM information_schema.table_privileges
                WHERE table_schema = 'public'
                  AND table_name = 'alembic_version'
                  AND grantee IN ('anon', 'authenticated')
                """
            )
        )
    ).all()
    assert not rows
