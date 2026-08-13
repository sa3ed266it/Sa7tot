# Sa7tot Testing

## 5.1 Testing Philosophy

Automated tests validate logic, contracts, ownership, and selected integration
behavior. A successful build validates compilation and packaging inputs. It
does not prove runtime UI interaction, animations, authentication transitions,
background execution, or APNs delivery.

A static screenshot does not prove animation or interaction behavior. Platform
and notification behavior requires a real runtime, and APNs lifecycle behavior
requires a physical device.

## 5.2 Test Inventory

### iOS XCTest

The app test sources are under:

```text
app/Sa7tot/Tests/
```

Current suites include authentication/session, API client, DTO/configuration,
bootstrap lifecycle, financial-store cache behavior, push-token lifecycle,
error/toast behavior, subscription catalog tests, and server-side subscription
reminder eligibility/delivery tests.

### Backend pytest

Backend tests are under:

```text
backend/tests/
backend/pure_tests/
```

They cover API behavior, budgets, configuration/test safety, profiles,
movements, push devices, recurrences, subscriptions, RLS metadata, and
performance-oriented movement behavior. Pure tests cover APNs response
classification, financial-calendar behavior, JWT/JWKS validation, and
transaction enrichment.

### Migration validation

Alembic provides revision and pending-operation checks. RLS metadata tests
inspect selected migration effects.

### Localization validation

`scripts/check_localization.py` validates the String Catalog.

### Build validation

The Xcode project is `app/Sa7tot.xcodeproj`, with the `Sa7tot` scheme. The
backend is built and run through its Python package configuration.

### Physical-device validation

The Development APNs lifecycle has been validated on a physical iPhone. This
is runtime evidence, not an automated test suite.

## 5.3 Backend Tests

From `backend/`, use an isolated test database:

```sh
APP_ENV=test TEST_DATABASE_URL=<disposable-postgresql-url> \
  .venv/bin/pytest tests pure_tests
```

The repository’s backend tests prove selected behavior including:

- Authenticated ownership and cross-user access behavior.
- Profile/bootstrap behavior.
- Account, category, transaction, transfer, and budget APIs.
- Push-device registration, validation, ownership, idempotent reassociation,
  and deactivation.
- APNs payload and response classification in `backend/pure_tests/test_apns.py`.
- Subscription reminder calendar eligibility, profile timezone/DST behavior,
  schedule-edit safety, durable idempotency, multi-device delivery,
  ownership, retry/deactivation handling, and privacy-conscious payloads in
  `backend/tests/test_subscription_reminders.py`.
- Subscription dates and materialization idempotency.
- Recurrence creation, lifecycle, upcoming projections, ownership, timezone,
  and concurrent materialization behavior.
- Configuration safety that prevents tests from using an unsafe database.
- RLS metadata expectations.

Do not point pytest at a shared staging or production database.

## 5.4 iOS Tests

The iOS test target contains suites such as:

- `SupabaseAuthTests.swift`
- `AuthRootLifecycleTests.swift`
- `RemoteAPIClientTests.swift`
- `RemoteDTOTests.swift`
- `RemoteValueAndConfigurationTests.swift`
- `FinancialRemoteStoreFilterCacheTests.swift`
- `PushTokenCoordinatorTests.swift`
- `AppErrorPresentationTests.swift`
- `AppToastTests.swift`
- `SubscriptionCatalogTests.swift`

The intended project/scheme is:

```text
app/Sa7tot.xcodeproj
Sa7tot
```

The full simulator XCTest target now resolves the `Sa7tot` module through the
host app target dependency and completes successfully. The current Debug
simulator run executed 115 tests with 0 failures and 0 skipped tests.

## 5.5 Push Testing Matrix

| Scenario | Automated | Simulator | Physical device | Status |
|---|---:|---:|---:|---|
| APNs token formatting | Yes | Not required | Not required | Covered by `PushTokenCoordinatorTests` |
| Registration request construction | Yes | Not required | Not required | Covered by coordinator/backend tests |
| Backend token upsert | Yes | Not required | Not required | Covered by `backend/tests/test_push.py` |
| Sign-out deactivation ordering | Yes | Not required | Yes | Verified |
| Sign-in reassociation/reactivation | Backend/client tests | Not required | Yes | Verified |
| APNs response classification | Yes | Not required | Not required | Covered by `backend/pure_tests/test_apns.py` |
| Sandbox delivery acceptance | No | No | Yes | Verified |
| Visible background receipt | No | No | Yes | Verified in Development/Sandbox |
| Production delivery | No | No | No | Not verified; Production APNs incomplete |
| Foreground presentation | No | No | No | Not verified; no current runtime proof |
| Notification tap routing | No | No | No | Not implemented |

Do not infer foreground presentation support from a background receipt.

## 5.6 Auth and Session Testing

Current automated coverage includes:

- Apple credential exchange and Supabase session decoding.
- Authenticated API bearer-token construction.
- Session refresh behavior and 401 handling.
- Bootstrap state/error behavior.
- Session-coordinator restore/refresh behavior using test session stores; the
  real Keychain implementation still requires runtime validation.
- Push deactivation ordering and failure safety through push-token tests.

Runtime validation remains required for:

- Actual Sign in with Apple on a signed build.
- Keychain persistence across terminate/relaunch.
- Real FastAPI JWT validation with the signed-in user.
- End-to-end bootstrap and profile reuse.
- Physical sign-out/re-login token lifecycle.

## 5.7 Financial and Materialization Testing

Backend tests cover:

- Account/category/transaction ownership.
- Transfer and financial API behavior.
- Subscription start-date and `next_billing_date` semantics.
- Subscription update attempts cannot override the backend-derived
  `next_billing_date`; schedule edits recalculate it and metadata edits
  preserve it.
- Subscription materialization idempotency.
- Recurrence lifecycle and idempotent materialization.
- Upcoming recurrence/subscription projections.
- Named timezone/calendar behavior.

The financial-calendar suite and subscription-reminder suite include
Europe/Rome daylight-saving boundary and named-timezone conversion coverage.

## 5.8 Localization Validation

Run from the repository root:

```sh
python3 scripts/check_localization.py
```

The checker is expected to catch malformed empty keys, language parity issues,
unresolved references, and placeholder incompatibilities.

Current status: the localization integrity checker passes.

## 5.9 Migration Validation

From `backend/`:

```sh
alembic current
alembic check
alembic upgrade head
```

- `alembic current` reports the database’s recorded revision.
- `alembic check` reports whether model metadata has unapplied operations.
- `alembic upgrade head` applies the repository migration chain to the latest
  revision and must be used only with the intended database.

The current reminder migration is `0008_subscription_reminders`. Its two
durable delivery tables and owner RLS policies are validated by the backend
suite.

Migration-specific RLS expectations are covered by
`backend/tests/test_rls_metadata.py`. These checks do not replace a production
change-review or backup procedure.

## 5.10 Local Deployment Foundation Checks

The production Docker and VPS templates are validated locally only. The
repeatable checks are:

```sh
docker build -f backend/Dockerfile -t sa7tot-api:local backend
SA7TOT_API_ENV_FILE=/path/to/non-secret/local.env \
SA7TOT_APNS_PRIVATE_KEY_FILE=/path/to/non-secret/placeholder.p8 \
docker compose -f backend/compose.production.yaml config
scripts/deploy/package-api-release.sh
```

The local container may be run with a disposable development/test database to
check `/health/live` and `/health/ready`. The release package must be scanned
for `.env`, `.p8`, secret material, `.git`, virtual environments, tests, and
personal absolute paths. Nginx and systemd files are reviewed or linted
offline when those tools are available; they are not installed by the
repository.

The future deployment layout is isolated under `/opt/sa7tot-api`, with an
external `shared/.env`, an external APNs key mount, an independent Compose
project, and a localhost-only API port. No production database, APNs
credential, server, DNS, TLS, or systemd state is part of this local test.

## 5.11 Physical Device Test Procedure

For Development APNs lifecycle validation:

1. Start FastAPI on the Mac, bound to `0.0.0.0`, with the iPhone and Mac on the
   same LAN.
2. Configure the Development app to use `http://<MAC_LAN_IP>:8000`.
3. Install the current app in place when session/container persistence matters.
4. Sign in and confirm authenticated bootstrap succeeds.
5. Confirm `PUT /v1/push/devices` succeeds without exposing the token.
6. Confirm one active `ios`/`development` token row and relaunch idempotency.
7. Put the app in the background and perform one approved Sandbox test push.
8. Confirm visible physical-device receipt.
9. Sign out and confirm the token becomes inactive before auth/session clear.
10. Sign in again and confirm the same logical token is active/reassociated.
11. Confirm there is no duplicate active token.
12. Perform the final background push receipt check.

See [Development](DEVELOPMENT.md) for LAN/build details and [Push
Notifications](push-notifications/README.md) for the APNs foundation record.

## 5.12 Known Issues

### Localization

The localization integrity checker passes.

Status: **PASS**.

## 5.13 Release Test Gate

A future release gate should require:

- Backend tests in an isolated test environment.
- iOS build success.
- A healthy XCTest target.
- Passing localization validation.
- Alembic revision/pending-operation checks.
- Secret and redaction review.
- Critical auth/bootstrap smoke validation.
- Physical APNs validation for the intended distribution environment.

Development/Sandbox APNs is validated. Production APNs is not complete and
must not be marked complete by a Development test.

## 5.14 Missing Coverage and Backlog

Evidence-based gaps include:

- Configure and validate Production APNs.
- Decide and test foreground notification presentation.
- Implement notification tap routing.
- Perform user-assisted physical Development/Sandbox subscription reminder
  validation and repeat-run idempotency verification.
- Define and validate backup/restore procedures.
- Add release-build smoke tests.
