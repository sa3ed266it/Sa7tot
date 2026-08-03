# Sa7tot

Sa7tot is a native iPhone personal-finance application written with SwiftUI. It has an Italian-first interface, local-first Core Data storage, optional iCloud/CloudKit synchronization, and is designed for private personal use.

## Features

- Expenses and income
- Financial accounts and account balances
- Transfers between accounts
- Budgets and recurring transactions
- Statistics and insights
- Multiple currencies
- Home and Lock Screen widgets
- Face ID and app lock
- iCloud synchronization
- Import/export where currently supported
- Apple Shortcuts and App Intents
- Merchant categorization and duplicate prevention
- Review queue for uncertain Wallet entries
- Italian localization

## Apple Wallet Automation

Sa7tot can receive a Wallet transaction through a user-created Apple Shortcuts Personal Automation:

```text
Apple Wallet transaction → Personal Automation in Shortcuts → Sa7tot App Intent → local expense record
```

The user must configure the automation in Apple Shortcuts. Availability depends on iOS, the card, the bank, and Wallet variables. Sa7tot does not scrape notifications and does not connect directly to a bank.

## Technology

- Swift
- SwiftUI
- Core Data
- `NSPersistentCloudKitContainer` and CloudKit
- WidgetKit
- App Intents and Shortcuts
- LocalAuthentication
- XCTest

## Requirements

- Xcode 26.6 was used for the current project build.
- iOS 15.0 or later for the app target.
- An Apple Developer signing team is required for device builds and for testing iCloud, CloudKit, App Groups, and Wallet-related integrations.
- Real Apple Wallet automation cannot be fully validated in the iOS Simulator; use a compatible physical device and Wallet configuration.

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
3. Configure the App Group and CloudKit container for the selected development team when building for a device or iCloud testing.
4. Build and run the `Sa7tot` scheme.

The repository does not contain secrets, signing credentials, or personal team configuration.

## Project Structure

- `app/Sa7tot` — main iPhone application, views, models, data, localization, and App Intents
- `app/ExpenditureWidget` — WidgetKit extension
- `app/BudgetIntent` — budget App Intent extension
- `app/BudgetIntentUI` — budget App Intent UI extension
- `app/MainModel.xcdatamodeld` — Core Data model

## Privacy

Financial data is stored locally and can synchronize through iCloud/CloudKit as implemented by the app. Sa7tot includes no advertising SDK, collects no bank credentials, and has no direct bank connection. Notification content should remain privacy-conscious when configuring Wallet automations.

## Current Status

Sa7tot is an active private/personal project. The native iOS interface refresh is ongoing.

## Open-Source Attribution

Sa7tot is based on the open-source [Dime project by Rafael Soh](https://github.com/rafsoh/dimeApp). Dime is licensed under the GNU GPL v3.0. Existing copyright notices are preserved in the source distribution.

## License

This derived project is distributed under GPL-3.0 where applicable. See [LICENSE](LICENSE) for the full license text.

