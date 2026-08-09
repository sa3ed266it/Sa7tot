# Sa7tot

Sa7tot is a native iPhone personal-finance application written with SwiftUI. Its financial data is remote-only through the authenticated FastAPI/Supabase backend, and it is designed for private personal use.

## Features

- Expenses and income
- Financial accounts and account balances
- Transfers between accounts
- Budgets and recurring transactions
- Multiple currencies
- Face ID and app lock
- Import/export where currently supported
- Merchant categorization and duplicate prevention
- Italian localization

## Technology

- Swift
- SwiftUI
- APIClient and authenticated remote repositories
- FastAPI and Supabase PostgreSQL
- Keychain-backed Supabase Auth
- LocalAuthentication
- XCTest

## Requirements

- Xcode 26.6 was used for the current project build.
- iOS 15.0 or later for the app target.
- An Apple Developer signing team is required for device builds and Sign in with Apple/APNs testing.

## Getting Started

Clone the repository and open the Xcode project:

```sh
git clone https://github.com/sa3ed266it/Sa7tot.git
cd Sa7tot
open app/Sa7tot.xcodeproj
```

In Xcode:

1. Select the `Sa7tot` scheme and an Apple Development team.
2. Allow Swift Package Manager to resolve the project dependencies. If needed, use **File > Packages > Resolve Package Versions**.
3. Build and run the `Sa7tot` scheme.

The repository does not contain secrets, signing credentials, or personal team configuration.

## Project Structure

- `app/Sa7tot` — main iPhone application, remote repositories, views, models, and localization
- `backend` — FastAPI service and Supabase database migrations

## Privacy

Financial data is loaded and saved through authenticated remote APIs. Sa7tot includes no advertising SDK, collects no bank credentials, and has no direct bank connection.

## Current Status

Sa7tot is an active private/personal project. The native iOS interface refresh is ongoing.

## Open-Source Attribution

Sa7tot is based on the open-source [Dime project by Rafael Soh](https://github.com/rafsoh/dimeApp). Dime is licensed under the GNU GPL v3.0. Existing copyright notices are preserved in the source distribution.

## License

This derived project is distributed under GPL-3.0 where applicable. See [LICENSE](LICENSE) for the full license text.
