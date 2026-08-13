# Sa7tot Development Guide

This guide covers local development and Development builds. It does not
describe Production deployment or release operations.

## 5.1 Prerequisites

- macOS with Xcode and an iOS SDK that can build the project.
- The project currently declares an iOS deployment target of 15.0; newer
  SwiftUI APIs are guarded in source where required.
- Python 3.12 or newer. The required version is declared by
  `backend/pyproject.toml`.
- A Python virtual environment with the backend development dependencies.
- PostgreSQL for local backend/test use, or a configured Supabase PostgreSQL
  database for staging validation.
- A paired Development-signing iPhone is required for physical-device APNs
  validation.

An exact macOS or Xcode version is not pinned in the repository. Use the
installed Xcode/toolchain appropriate for the target device and simulator.

## 5.2 Repository Layout

```text
app/       SwiftUI iOS app, remote repositories, views, and XCTest target
backend/   FastAPI app, SQLAlchemy models/services, Alembic, and backend tests
docs/      Current and archived project documentation
scripts/   Repository validation and subscription-logo tooling
```

## 5.3 Backend Setup

The backend uses a local ignored `.env` file and a virtual environment:

```sh
cd backend
python3 -m venv .venv
.venv/bin/pip install -e '.[dev]'
cp .env.example .env
```

For a basic local database, configure `APP_ENV=development` and
`DATABASE_URL` in `backend/.env`. For authenticated routes, also configure
the Supabase Auth URL described below.

Apply the current schema and start the API:

```sh
alembic upgrade head
.venv/bin/uvicorn app.main:app --reload
```

The backend defaults to port `8000`. The health endpoint is:

```sh
curl http://127.0.0.1:8000/health
```

There is no repository-specific `scripts/dev` API wrapper; use the commands
above or an equivalent local process configuration.

## 5.4 Environment Variables

Never copy real credentials into documentation or source control.

### Basic backend configuration

- `APP_ENV` — normally `development`; use `test` for isolated backend tests.
- `DATABASE_URL` — PostgreSQL/asyncpg connection URL for development or
  staging.
- `TEST_DATABASE_URL` — disposable PostgreSQL URL required when `APP_ENV=test`.

### Supabase authentication configuration

- `SUPABASE_URL` — Supabase project URL used to derive the Auth issuer and JWKS
  endpoint for JWT validation.
- `SUPABASE_AUDIENCE` — JWT audience; defaults to `authenticated`.

Database startup, migrations, and `/health` do not require the Auth URL, but
authenticated routes do.

### Development APNs configuration

- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID` — normally `com.saied.sa7tot`.
- `APNS_PRIVATE_KEY_PATH` — path to an external `.p8` file.
- `APNS_ENVIRONMENT` — `development` for Sandbox or `production` for the
  corresponding APNs endpoint.

### Optional backend configuration

- `INTERNAL_JOB_SECRET` — optional internal-job authentication value.
- `PAGE_SIZE_DEFAULT` and `PAGE_SIZE_MAX` — optional pagination limits.

The exact configuration fields are defined in `backend/app/core/config.py`.

Keep `backend/.env` and `.p8` files outside version control. The repository
ignores `backend/.env`, `*.p8`, the backend virtual environment, and generated
Python/Xcode output.

## 5.5 Running the Backend Locally

From `backend/`:

```sh
.venv/bin/uvicorn app.main:app --reload
curl http://127.0.0.1:8000/health
```

For a physical iPhone on the same LAN, bind the development server to all
interfaces:

```sh
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

The health endpoint is a process/configuration check and does not expose
database details.

## 5.6 Physical iPhone and LAN Backend Workflow

1. Connect the Mac and iPhone to the same LAN.
2. Find the Mac's current LAN IP using the operating system's network tools.
3. Start FastAPI with `--host 0.0.0.0 --port 8000`.
4. Configure the Development app's non-secret `API_BASE_URL` as:
   `http://<MAC_LAN_IP>:8000`.
5. Build and install the app using the paired Development signing setup.
6. Verify the backend is reachable before testing authenticated screens or
   APNs registration.

The LAN IP can change. Do not hard-code a historical address.

The app's `API_BASE_URL` is an Xcode build setting resolved into
`app/Sa7tot/Info.plist`. `APIConfiguration.current` reads a process-environment
override first and otherwise reads the bundled value. The Debug project
configuration defaults to `http://127.0.0.1:8000`.

For a physical build, set the build setting or build invocation to the LAN
placeholder value rather than editing application source code. The URL must
not contain credentials, a query, or a fragment.

## 5.7 Simulator Backend URL

The iOS Simulator runs on the Mac, so the current Debug default is:

```text
http://127.0.0.1:8000
```

Start FastAPI on the Mac and use the normal Debug configuration. Do not use
Android-specific host aliases.

## 5.8 Build the iOS App

The Xcode project and main target are:

```text
Project: app/Sa7tot.xcodeproj
Target/Scheme: Sa7tot
```

Example simulator build:

```sh
xcodebuild \
  -project app/Sa7tot.xcodeproj \
  -scheme Sa7tot \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

Use Xcode's paired-device Development configuration for a physical build.
The app bundle ID is `com.saied.sa7tot`; the current source version is
`1.0.0 (1)`.

## 5.9 In-Place Physical Device Installation

When testing session restoration or APNs lifecycle behavior, install the new
Development build over the existing app with the same bundle ID through
Xcode's normal paired-device Run/install flow.

Do not uninstall the app first when preserving the existing container/session
matters. In-place installation preserves the app container where iOS permits,
but this is not a guarantee against every OS, signing, or installation change.

The repository does not define a custom installer or destructive device-reset
workflow.

## 5.10 Development Push Testing

See [Push Notifications](push-notifications/README.md) for the complete
foundation and validation record.

The environment relationship is strict:

```text
Development app / aps-environment=development
  → development token rows
  → Sandbox APNs
```

The development test-push script is a backend utility, not a public API. Do
not send development tokens to the Production APNs endpoint.

## 5.11 Database and Alembic Basics

From `backend/`, the safe current checks are:

```sh
alembic current
alembic check
alembic upgrade head
```

The migration files under `backend/alembic/versions/` define schema changes.
Production migration, backup, and rollback procedures are intentionally not
covered by this development guide.

## 5.12 Common Development Validation

### Backend tests

Backend tests require an isolated test database and `APP_ENV=test`:

```sh
cd backend
APP_ENV=test TEST_DATABASE_URL=<disposable-postgresql-url> \
  .venv/bin/pytest tests pure_tests
```

Do not point pytest at a shared staging or production database.

### Localization validation

From the repository root:

```sh
python3 scripts/check_localization.py
```

### iOS build and diff checks

```sh
xcodebuild \
  -project app/Sa7tot.xcodeproj \
  -scheme Sa7tot \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

git diff --check
```

### Known development issue

The full simulator XCTest target has encountered:

```text
Unable to resolve module dependency: 'Sa7tot'
```

This is a separate engineering issue. Do not treat a successful build alone as
proof that the full simulator XCTest target is healthy.

## 5.13 Localization Note

The app's Italian and English catalog is:

```text
app/Localizable.xcstrings
```

The validation script is:

```text
scripts/check_localization.py
```

The localization integrity checker currently passes. It validates catalog
parity, referenced keys, placeholders, and the absence of legacy resources.

## 5.14 Security Rules for Local Development

- Never commit `backend/.env` or any other secret environment file.
- Never commit `.p8` files or private-key contents.
- Never print full APNs device tokens.
- Never log access/refresh JWTs, private keys, database passwords, or service-role credentials.
- Use placeholders in documentation and shell examples.
- Keep physical-device API URLs free of credentials.
- Use a disposable database for backend tests.

## 5.15 Troubleshooting Pointers

- **iPhone cannot reach the backend:** confirm the Mac and iPhone share a LAN,
  FastAPI is bound to `0.0.0.0`, the firewall allows port 8000, and
  `API_BASE_URL` uses the current Mac LAN IP.
- **LAN address changed:** find the current address and rebuild/configure the
  Development app; do not hard-code it in source.
- **Simulator cannot load data:** confirm FastAPI is running on the Mac at
  `127.0.0.1:8000` and that the Debug API setting was not overridden.
- **APNs rejects a push:** check Development/Sandbox versus Production
  environment, token rows, topic, and signing entitlement alignment.
- **XCTest module resolution fails:** see the known `Sa7tot` module issue in
  section 5.12; it is not fixed by this guide.
