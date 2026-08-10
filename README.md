# Sa7tot

Sa7tot is a personal finance iPhone app built around an account-first view of
money. It helps track expenses and income, move money between accounts, manage
subscriptions and categories, and review budgets and upcoming financial
activity through a clean Apple-native interface.

## Overview

Movimenti is organized around the selected account: balances, transactions,
filters, and transfer perspective follow the account currently being viewed.
The app also provides transaction details, notes, category and account
management, subscriptions, recurring transaction rules, upcoming movements,
and budget summaries.

Financial data is remote-only. The iOS app uses authenticated FastAPI APIs for
application data, with Supabase PostgreSQL behind the backend. The app supports
Italian and English.

## Features

- Account-first balances and transaction filtering
- Expense and income tracking
- Account-to-account transfers
- Categories with SF Symbols and colors
- Transaction details and notes
- Subscription catalog, local logos, and renewal materialization
- Recurring transaction rules and upcoming movement views
- Main and category budgets
- Multiple currencies and account-relative financial calculations
- Sign in with Apple with Keychain-backed session restoration
- Optional app lock using the device's local authentication capabilities
- Native SwiftUI and UIKit integrations for the iPhone interface

## Architecture

Application and financial data follows this path:

```text
┌──────────────┐       HTTPS/JSON       ┌──────────────┐
│  Sa7tot iOS  │ ─────────────────────▶ │   FastAPI    │
└──────────────┘                        └──────┬───────┘
                                               │ SQLAlchemy / asyncpg
                                               ▼
                                        ┌──────────────┐
                                        │  Supabase    │
                                        │ PostgreSQL   │
                                        └──────────────┘
```

Authentication is separate from financial persistence:

```text
Sign in with Apple → Supabase Auth → Keychain session → authenticated FastAPI requests
```

The iOS app uses Supabase directly for authentication and session handling. It
does not use Core Data or CloudKit for financial storage, and it does not
provide offline financial writes.

## Tech Stack

- Swift 5 and SwiftUI
- UIKit for native iOS integrations, including the tab bar
- FastAPI and Python
- SQLAlchemy 2.x with asyncpg
- PostgreSQL and Supabase
- Alembic migrations
- Sign in with Apple and Supabase Auth
- Lottie, CrookedText, and ConfettiSwiftUI
- XCTest, pytest, and Ruff

## Project Structure

```text
Sa7tot/
├── app/
│   └── Sa7tot/          # iOS app, remote stores, views, assets, and tests
├── backend/
│   ├── app/             # FastAPI API, services, repositories, and models
│   ├── alembic/         # PostgreSQL migrations
│   └── tests/           # Backend tests
├── docs/                # Current project documentation
│   └── archive/         # Historical audits and migration material
├── scripts/             # Localization and subscription-logo tooling
├── README.md
└── LICENSE
```

## Requirements

### iOS

- macOS with Xcode and an iOS Simulator or development device
- Swift 5.0 toolchain
- The project deployment target is iOS 15.0
- The current remote financial interface is conditionally available on iOS 26.0 and later
- An Apple Developer signing team for device builds and Sign in with Apple testing

### Backend

- Python 3.12 or newer
- PostgreSQL; SQLite is not supported for runtime or database tests
- A local PostgreSQL database or a dedicated Supabase PostgreSQL environment

## Getting Started

### iOS app

Clone the repository and open the Xcode project:

```sh
git clone https://github.com/sa3ed266it/Sa7tot.git
cd Sa7tot
open app/Sa7tot.xcodeproj
```

Select the `Sa7tot` scheme and a development signing team. The Debug build
defaults to a local backend at `http://127.0.0.1:8000`. For a simulator or
device using another backend, provide a development `API_BASE_URL` through
local Xcode build settings or the process environment.

Authentication configuration uses the existing `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY` configuration names. Use your own development
values through local configuration; do not add credentials to source control.

Start the backend before launching the app when using the local API.

### Backend

```sh
cd backend
python3 -m venv .venv
.venv/bin/pip install -e '.[dev]'
cp .env.example .env
```

Set `APP_ENV=development` and a PostgreSQL `DATABASE_URL` in the ignored
`.env` file. To use authenticated API routes, also set the development
`SUPABASE_URL` for the Supabase project. Then run:

```sh
.venv/bin/alembic upgrade head
.venv/bin/uvicorn app.main:app --reload
```

The API health endpoint is available at `http://127.0.0.1:8000/health`.
See [backend setup and validation](backend/README.md) for migrations,
Supabase staging, seed data, and database checks.

## Authentication

The iOS app authenticates users with Sign in with Apple and exchanges the Apple
credential with Supabase Auth. Supabase sessions are stored in the Keychain and
refreshed through the app's authentication coordinator. Authenticated API
requests receive the current Supabase access token through the existing token
provider; FastAPI validates the JWT before resolving the user's remote profile
and financial data.

See [Authentication Foundation](docs/AUTHENTICATION_FOUNDATION.md) for the
current authentication contract.

## Localization

The app supports English and Italian through the string catalog at
`app/Localizable.xcstrings`. Localization parity is checked with:

```sh
python3 scripts/check_localization.py
```

## Development / Validation

Run the iOS tests and build with:

```sh
xcodebuild test \
  -project app/Sa7tot.xcodeproj \
  -scheme Sa7tot \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

xcodebuild build \
  -project app/Sa7tot.xcodeproj \
  -scheme Sa7tot \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

For backend checks:

```sh
cd backend
.venv/bin/ruff check .
.venv/bin/ruff format --check .
APP_ENV=test TEST_DATABASE_URL=postgresql+asyncpg://localhost/sa7tot_test \
  .venv/bin/pytest
```

Backend tests require an isolated disposable PostgreSQL database. They must
use `APP_ENV=test` and an explicit `TEST_DATABASE_URL`; never point destructive
tests at development, staging, or production data.

## Documentation

- [Authentication Foundation](docs/AUTHENTICATION_FOUNDATION.md)
- [Subscription Logos](docs/SUBSCRIPTION_LOGOS.md)
- [Archived audits and migration material](docs/archive/)
- [Backend README](backend/README.md)

## Current Project Status

Sa7tot is under active development as a personal iOS finance application. The
current financial path is remote-only through the authenticated backend.

## Open-Source Attribution

Sa7tot is based on the open-source [Dime project by Rafael Soh](https://github.com/rafsoh/dimeApp).
Dime is licensed under the GNU GPL v3.0. Existing copyright notices are
preserved in the source distribution.

## License

This derived project is distributed under GPL-3.0 where applicable. See
[LICENSE](LICENSE) for the full license text.
