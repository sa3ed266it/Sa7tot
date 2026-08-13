# Sa7tot Backend Foundation V1.1

This directory contains the remote backend for Sa7tot. The iOS app accesses
application and financial data through authenticated FastAPI APIs, with
Supabase PostgreSQL behind the backend. Direct Supabase use in iOS is limited
to authentication and session handling.

```text
SwiftUI network client/repositories -> HTTPS/JSON -> FastAPI -> SQLAlchemy async -> PostgreSQL/Supabase
```

## Scope

Implemented:

- FastAPI `/health` endpoint and versioned `/v1` routes;
- PostgreSQL-only SQLAlchemy 2.x async access;
- Pydantic DTOs and PostgreSQL constraints/indexes;
- profiles, accounts, categories, transactions, budgets, subscriptions, recurrence rules, and occurrences;
- integer minor-unit money values;
- explicit authenticated-user ownership checks;
- account-relative balances and transfers, including `creditCard` behavior;
- cursor-paginated Movimenti responses;
- subscription scheduling and idempotent materialization;
- server-side seven-day subscription renewal reminder eligibility, durable
  multi-device delivery state, and Development/Sandbox CLI sending;
- Alembic migration from an empty PostgreSQL database.

Not included in this backend:

- historical local-data migration;
- a production scheduler such as `pg_cron`.

The reminder runner is intentionally provider-agnostic and is invoked hourly
by an external scheduler. Development/Sandbox physical subscription-reminder
receipt and idempotent repeat-run behavior are validated. Production APNs and
production hosting remain unconfigured and unvalidated.

## Minimum local/staging configuration

Normal backend startup and Alembic only require these two values:

```dotenv
APP_ENV=development
DATABASE_URL=postgresql+asyncpg://localhost/sa7tot
```

Copy `.env.example` to `.env` for a local-only file. Never put credentials in
`.env.example` or source control.

The connection URL may use either `postgresql+asyncpg://...` or the common
`postgres://...`/`postgresql://...` form; the backend normalizes the latter to
the asyncpg driver. Supabase direct and pooler URLs are supported, for example:

```text
postgresql+asyncpg://postgres:PASSWORD@db.PROJECT_REF.supabase.co:5432/postgres?sslmode=require
postgresql+asyncpg://postgres.PROJECT_REF:PASSWORD@aws-0-REGION.pooler.supabase.com:6543/postgres?pgbouncer=true&sslmode=require
```

Use a URL-encoded password when it contains URL-reserved characters. Supabase
connections receive TLS automatically when the URL requests `sslmode=require`
or the host is a Supabase direct/pooler host. No Supabase SDK, PostgREST client,
service-role key, or credential is used by this backend.

## Run and migrate

Python 3.12 or newer is recommended. PostgreSQL is required; SQLite is not a
supported test or runtime database.

```sh
cd backend
python3 -m venv .venv
.venv/bin/pip install -e '.[dev]'
cp .env.example .env
alembic upgrade head
.venv/bin/uvicorn app.main:app --reload
```

Health check:

```sh
curl http://127.0.0.1:8000/health
```

The deployment foundation also provides `/health/live` for process liveness
and `/health/ready` for a minimal PostgreSQL readiness check.

The health endpoint is intentionally a process/configuration check and does
not expose database details.

For a fresh database, the complete lifecycle is:

```sh
alembic upgrade head
alembic check
alembic downgrade base
alembic upgrade head
```

## Supabase staging

Use a dedicated empty staging project and the PostgreSQL connection details
from its Connect panel. For this persistent FastAPI backend, the supplied
session-pooler URL is supported; direct PostgreSQL is also suitable when the
network supports it.

1. Create or select the Supabase staging project.
2. Copy the PostgreSQL connection string from the Supabase Connect panel into
   the ignored local `.env` file:

   ```dotenv
   APP_ENV=development
   DATABASE_URL=postgresql+asyncpg://USER:PASSWORD@POOLER_HOST:5432/postgres?sslmode=require
   ```

3. Apply the schema: `alembic upgrade head`.
4. Check the revision: `alembic current` and `alembic check`.
5. Seed one explicit development UUID:
   `python -m app.scripts.seed_dev --user-id UUID`.
6. Run `python -m app.scripts.smoke_db`.
7. Start FastAPI and call `GET /health`.

No Dashboard table creation is required. Authentication configuration remains
separate from database startup and Alembic operations.

## Current authentication configuration

Sign in with Apple is active in the iOS app through Supabase Auth. The iOS
client persists and restores the Supabase session in Keychain, and authenticated
FastAPI requests carry the Supabase bearer token. FastAPI validates the token
and derives application-data ownership from the authenticated subject; the
client cannot choose an arbitrary user identity.

For authenticated backend routes, configure:

```dotenv
SUPABASE_URL=https://your-project.supabase.co
```

The backend derives the issuer as `${SUPABASE_URL}/auth/v1` and JWKS endpoint
as `${SUPABASE_URL}/auth/v1/.well-known/jwks.json`. The normal Supabase
audience defaults to `authenticated`. JWKS, issuer, and audience do not need
to be manually collected for database startup or Alembic.

Authentication configuration is lazy: `/health`, migrations, database smoke
checks, and tests using an explicit principal override work without
`SUPABASE_URL`. Authenticated routes return a configuration error until the
URL is provided; they never fall back to a development user or bypass JWT
validation.

The active flow is:

```text
Sign in with Apple -> Supabase Auth -> Supabase JWT -> FastAPI JWT validation
```

## Ownership and RLS status

Every authenticated service query includes the validated `user_id`; this is the
mandatory FastAPI ownership boundary and is covered by PostgreSQL integration
tests. Cross-user reads/writes return the same not-found behavior as an absent
record.

The initial Alembic migration also enables PostgreSQL RLS and installs
owner-policy helpers based on `request.jwt.claim.sub`. The direct PostgreSQL
application role normally owns these tables, so PostgreSQL owner bypass means
FastAPI must not rely on those policies for isolation. Claim-based RLS is
defense in depth only until a non-owner role/session-claim setup is provisioned
and verified. The migration does not pretend that enabling the policy alone is
end-to-end Supabase RLS enforcement.

## Development seed data

Seed data is deterministic per explicit user UUID, idempotent, and limited to
the records created by this utility. It includes a profile, two EUR accounts,
two categories, representative income/expense/transfer records, and a Netflix
subscription.

```sh
python -m app.scripts.seed_dev --user-id 11111111-1111-1111-1111-111111111111
python -m app.scripts.seed_dev --user-id 11111111-1111-1111-1111-111111111111 --reset --allow-development-reset
```

The command refuses `APP_ENV=production` unless the operator explicitly adds
`--force-production`. It never creates an auth bypass and does not print
connection strings or secrets. `--reset` deletes only the deterministic seed
records, requires explicit reset intent in development, and will fail rather
than remove unrelated records that depend on them. Never run `--reset` against
the shared staging database.

## Database smoke check

After provisioning a staging project and applying migrations:

```sh
python -m app.scripts.smoke_db
```

The command performs a connection check, `SELECT 1`, and reads the Alembic
version. It prints only status/version information, never the database URL or
password.

## Tests and lint

Automated tests are isolated from development, Supabase staging, and
production. Destructive fixtures require both `APP_ENV=test` and an explicit
`TEST_DATABASE_URL`; there is no fallback to `DATABASE_URL`. The test database
must be PostgreSQL and its database name must contain `test`. Supabase hosts
and the configured application database are rejected before pytest starts.

Create the disposable database once, apply migrations to that database, and
run pytest with the test-only environment:

```sh
createdb sa7tot_test
APP_ENV=test TEST_DATABASE_URL=postgresql+asyncpg://localhost/sa7tot_test \
  alembic upgrade head
APP_ENV=test TEST_DATABASE_URL=postgresql+asyncpg://localhost/sa7tot_test \
  pytest tests pure_tests
APP_ENV=test TEST_DATABASE_URL=postgresql+asyncpg://localhost/sa7tot_test \
  ruff format --check .
APP_ENV=test TEST_DATABASE_URL=postgresql+asyncpg://localhost/sa7tot_test \
  ruff check .
```

If `TEST_DATABASE_URL` is missing, `APP_ENV` is not `test`, the target is the
same database as `DATABASE_URL`, the target is a Supabase host, or its database
name has no explicit `test` marker, the test setup fails closed. Do not source
the staging `.env` as a substitute for `TEST_DATABASE_URL`.

Live staging validation is a separate, non-pytest workflow. It may use
`APP_ENV=development` and `DATABASE_URL`, but destructive seed reset requires
the explicit `--allow-development-reset` flag and is refused in production.
Normal `smoke_db` only performs read-only connectivity and migration checks.

For a safe Development/Sandbox reminder inspection or send:

```sh
python -m app.scripts.send_subscription_reminders --environment development --dry-run
python -m app.scripts.send_subscription_reminders --environment development
```

The runner uses profile-local timezone/date semantics, never logs tokens or
financial amounts, and does not accept a user ID from the command line.

Coverage includes ownership and archive behavior, category soft delete,
expense/income/transfer creation, currency rejection, Movimenti balance and
perspective/pagination, credit-card semantics, monthly end-of-month and yearly
leap scheduling, pause/resume/cancel, materialization idempotency, timestamp
versus scheduled date, and cross-user subscription access.
