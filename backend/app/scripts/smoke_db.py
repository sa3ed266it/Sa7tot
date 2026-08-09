from __future__ import annotations

import asyncio

from sqlalchemy import text

from app.core.database import engine


async def run_smoke_check() -> None:
    async with engine.connect() as connection:
        await connection.execute(text("SELECT 1"))
        migration = await connection.scalar(text("SELECT version_num FROM alembic_version LIMIT 1"))

    print("database: connected")
    print(f"migration: {migration or '<none>'}")
    print("select: ok")


def main() -> None:
    asyncio.run(_run())


async def _run() -> None:
    try:
        await run_smoke_check()
    finally:
        await engine.dispose()


if __name__ == "__main__":
    main()
