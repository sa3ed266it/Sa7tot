# Sa7tot Operations

This document covers operational procedures that are knowable from the
repository. The authoritative future Sa7tot VPS is `root@89.167.101.23`;
production domain, TLS, monitoring, backup, and other operational policies
remain explicitly marked where they are not defined.

## 3.1 Scope

The repository defines the FastAPI application, database configuration,
Alembic migrations, authenticated ownership checks, and APNs provider client.
The authoritative future VPS is documented as `root@89.167.101.23`, but the
domain, TLS termination, monitoring provider, and backup vendor remain
undecided. A local Docker, Compose, Nginx, release-packaging, and
systemd-template foundation now exists under `backend/`, `scripts/deploy/`,
and `docs/deployment/`; it is not a deployment and has not touched a VPS.

## 3.1.1 Local Production Deployment Foundation

The future Sa7tot deployment is an isolated Compose project on a Linux VPS:

```text
Production host: root@89.167.101.23
Compose project: sa7tot-api
Local API binding: 127.0.0.1:8010
```

```text
/opt/sa7tot-api/
├── releases/<immutable-release>/
├── shared/.env
├── shared/apns-private-key.p8
└── current -> releases/<active-release>
```

The API container listens on port `8000` internally and is intended to bind
only to `127.0.0.1:${SA7TOT_API_HOST_PORT:-8010}` on the host. The database
remains external PostgreSQL/Supabase; no database container is part of the
Compose template. Nginx/TLS stays on the host and is represented only by
`docs/deployment/sa7tot-api-nginx.conf.example`.

Build and local package commands are intentionally separate from remote
operations:

```sh
docker build -f backend/Dockerfile backend
docker compose -f backend/compose.production.yaml config
scripts/deploy/package-api-release.sh
```

The Compose file requires an external `SA7TOT_API_ENV_FILE` and an external
read-only `SA7TOT_APNS_PRIVATE_KEY_FILE`. Neither is copied into the image or
release package. The default host port is a documented intention, not a claim
that a future server port is free.

Production setup must explicitly preflight the host port and database
revision, apply migrations as a separate guarded operator step, validate the
new release's health, and only then switch `current`. Application rollback
must use a retained immutable release and must never automatically downgrade
the database.

The reminder timer template uses a one-shot Compose run with `flock` to avoid
obvious concurrent invocations. Database idempotency remains the correctness
boundary. The service and timer are templates only and have not been
installed or enabled.

Future operator connection example:

```sh
ssh root@89.167.101.23
```

Patente_Facile remains a separate application on the same VPS. Sa7tot must
not reuse its Compose project, environment, secrets, release root, or
containers, and a port conflict on `8010` remains a preflight failure.

## 3.2 Runtime Components

| Component | Operational responsibility |
|---|---|
| FastAPI | Serves authenticated application and financial APIs and the `/health` endpoint |
| Supabase Auth | Provides user identity, sessions, issuer, and JWKS used for JWT validation |
| Supabase PostgreSQL | Stores profiles, accounts, categories, movements, budgets, subscriptions, recurrences, and push-device rows |
| Alembic | Applies and verifies schema migrations under `backend/alembic/versions/` |
| Backend APNs provider | Sends provider-authenticated HTTP/2 pushes to Apple APNs |
| iOS clients | Authenticate, call FastAPI, register APNs devices, and render server-confirmed data |

## 3.3 Environment Separation

Known environment concepts are:

- Local development: `APP_ENV=development`, local or Supabase PostgreSQL,
  and a Debug iOS build.
- Physical-device Development: a Development-signed app using a LAN API URL
  and development APNs registration.
- APNs development: development token rows and the Sandbox APNs endpoint.
- Tests: `APP_ENV=test` with a separate `TEST_DATABASE_URL`.
- Future Release/Production: production app signing, production APNs, and a
  production backend configuration that are not yet fully validated.

`STAGING: NOT DEFINED IN REPOSITORY` as a distinct deployable environment.
The backend README describes Supabase staging validation, but no staging host,
process, domain, or deployment configuration is committed.

## 3.4 Backend Configuration and Secrets

Configuration names are defined in `backend/app/core/config.py` and the safe
template `backend/.env.example`.

### Application and database

- `APP_ENV` — application environment selection.
- `DATABASE_URL` — PostgreSQL/asyncpg connection URL.
- `TEST_DATABASE_URL` — disposable test database URL when `APP_ENV=test`.

### Auth/JWT

- `SUPABASE_URL` — Supabase Auth project URL.
- `SUPABASE_AUDIENCE` — JWT audience, defaulting to `authenticated`.

### APNs

- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY_PATH`
- `APNS_ENVIRONMENT`

### Other configured values

- `INTERNAL_JOB_SECRET`
- `PAGE_SIZE_DEFAULT`
- `PAGE_SIZE_MAX`

Operational security rules:

- Keep `backend/.env` untracked.
- Keep `*.p8` untracked and outside the repository.
- Never print JWTs, private-key contents, full APNs tokens, database passwords,
  or service-role credentials.
- Use placeholders in operational notes and commands.

## 3.5 Backend Startup and Service Expectations

Developer startup from `backend/` is:

```sh
.venv/bin/uvicorn app.main:app --reload
```

For LAN access from a physical iPhone:

```sh
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Future production startup foundation: the independent `sa7tot-api` Compose
project, with the reminder systemd service/timer and Nginx files under
`scripts/deploy/` and `docs/deployment/`. None has been installed or enabled.

## 3.6 Health and Readiness

The backend exposes:

```text
GET /health
```

It is a safe process/configuration health check. It does not expose database
details and does not by itself prove that every authenticated route, database
query, migration, or APNs credential is ready.

Authenticated application readiness additionally depends on Supabase Auth
configuration, valid JWTs, database connectivity, current migrations, and
successful application bootstrap.

## 3.7 Database Migration Operations

From `backend/`, inspect and validate the current revision with:

```sh
alembic current
alembic check
```

Review pending migration files before applying them, then use the repository's
standard upgrade command:

```sh
alembic upgrade head
```

Operational rules:

- Review the migration source and expected compatibility before applying it.
- Establish a backup/restore strategy before risky production schema changes.
- Do not assume a downgrade is lossless; migrations may change or remove data.
- Verify `alembic current` and `alembic check` after an applied migration.
- Do not run these commands against a shared environment without explicit
  environment and change approval.

The current migration chain includes `0008_subscription_reminders` after
`0007_push_device_tokens`. A production migration runbook and rollback policy
are not defined in this repository.

## 3.8 RLS and Ownership Operational Rule

RLS is defense-in-depth for ordinary/direct database roles. Privileged backend
access may bypass ordinary RLS enforcement. FastAPI must therefore validate the
JWT and apply authenticated ownership checks on every user-owned operation.

See [Architecture](ARCHITECTURE.md), [Backend README](../backend/README.md),
and the migration files under `backend/alembic/versions/`.

## 3.9 APNs Operational Model

The environment relationship is strict:

```text
Development build
  → development token
  → Sandbox APNs

Release/Production build
  → production token
  → Production APNs
```

Tokens are environment-specific. Production APNs credentials, production
signing, and production delivery validation are not yet configured or
validated.

See [Push Notifications](push-notifications/README.md) for provider details
and the completed Development/Sandbox validation.

The subscription reminder runner is intentionally hosting-provider agnostic.
Invoke it hourly through an external scheduler:

```sh
python -m app.scripts.send_subscription_reminders --environment development
```

Use `--dry-run` for inspection. Production requires matching production
configuration and explicit `--allow-production`; production delivery remains
unvalidated.

## 3.10 Push Token Hygiene

The current lifecycle supports:

- Active and inactive device registrations.
- Sign-out deactivation before auth/session clear.
- Sign-in reassociation/reactivation.
- Environment-specific token rows.
- Deactivation candidates for permanent APNs errors such as
  `BadDeviceToken` and `Unregistered`.

Inactive-token retention/cleanup policy: **NOT YET DEFINED**.

## 3.11 Logging and Redaction

Operational logs may record safe status or reason information, such as HTTP
status codes and APNs reason categories. They must not contain:

- Full APNs device tokens.
- JWT access or refresh tokens.
- Private-key contents.
- Database passwords.
- Supabase service-role credentials.

Structured production logging, centralized log retention, alerting, and
redaction observability are not implemented or documented in the repository.

## 3.12 Backup and Recovery

Production backup/restore procedure: **NOT DOCUMENTED / REQUIRES HUMAN
INFRASTRUCTURE INPUT**.

A future operations runbook must establish:

- Supabase/PostgreSQL backup owner.
- Backup frequency and retention.
- Restore testing frequency and evidence.
- Pre-migration snapshot/backup policy.
- Recovery point objective and recovery time objective.

No repository evidence proves a production backup schedule or restore drill.

## 3.13 Secret Rotation

For any suspected compromise:

1. Revoke or replace the secret at its provider.
2. Update the ignored backend environment or deployment secret manager.
3. Restart/redeploy the backend through the eventual approved process.
4. Validate health, authenticated API behavior, and affected provider calls.
5. Remove the old credential from active configuration.
6. If accidental exposure occurred, scan repository history and follow the
   incident process rather than merely deleting the working-tree copy.

This applies to APNs keys, database credentials, Supabase/backend secrets, and
Apple authentication credentials. Provider-specific rotation procedures are
not defined in this repository.

## 3.14 Incident Checklist

### Backend unavailable

- Check the process and `GET /health`.
- Verify the configured API host/port and network reachability.
- Inspect redacted process errors without exposing configuration secrets.

### Database unavailable

- Check `DATABASE_URL` configuration without printing it.
- Check the database provider/network and migration state.
- Do not bypass authentication or ownership checks to recover service.

### Authentication failures

- Verify `SUPABASE_URL`, issuer, audience, JWKS reachability, and session state.
- Confirm the client is sending a current bearer token.
- Do not add a development-user or JWT-validation bypass.

### APNs rejection spike

- Confirm build/token/endpoint environment alignment.
- Check safe APNs reason categories such as `BadDeviceToken`,
  `DeviceTokenNotForTopic`, `InvalidProviderToken`, and
  `ExpiredProviderToken`.
- Deactivate only invalid-token candidates according to the existing service
  behavior.

### Migration failure

- Stop further schema changes.
- Preserve the error and migration revision.
- Determine recovery from the approved backup/restore procedure once defined.
- Do not improvise destructive downgrades.

### Suspected secret exposure

- Revoke/rotate the affected credential immediately.
- Keep secrets out of logs and issue reports.
- Check tracked files and repository history.
- Revalidate the affected service after rotation.

## 3.15 Unknown Production Infrastructure

| Concern | Repository status | Human decision required |
|---|---|---|
| Hosting provider | VPS host documented as `root@89.167.101.23`; not provisioned by this repository | Confirm server access and ownership |
| Domain | Not defined | Choose public API domain |
| TLS termination | Not defined | Define certificate and termination boundary |
| Reverse proxy | Nginx template exists; not installed | Install only after choosing the real API domain and TLS paths |
| Process manager/container | Compose and systemd templates exist; not installed | Perform guarded first deployment and service installation |
| Production Supabase project | Not defined in deployment files | Identify production project and access owners |
| Production APNs credentials | Not completed | Create and secure production provider credentials |
| Monitoring/alerting | Not defined | Select signals, owners, and escalation path |
| Backup policy | Not documented | Define frequency, retention, restore tests, and RPO/RTO |
| Staging environment | Not defined as a deployable environment | Decide whether a persistent staging environment is required |
