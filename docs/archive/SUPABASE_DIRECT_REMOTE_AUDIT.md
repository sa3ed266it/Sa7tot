# Sa7tot — Supabase Direct-Remote Architecture Audit

## Executive summary

The requested direct-remote architecture is feasible, but the current migration risk is **High** and implementation must not start from the current build state. The app has one Core Data/CloudKit-centric `DataController` shared with the app, widget, and intent targets; 43 `@FetchRequest` occurrences, 47 `NSFetchRequest` occurrences, 8 explicit Core Data imports, 12 WidgetKit imports, 11 `WidgetCenter` references, and 161 App Group suite references. Financial persistence currently uses `Double`. The safest target is authenticated Supabase Postgres with RLS, server-confirmed repository writes, one transfer RPC, and Realtime only for live domain tables.

## Verified baseline

| Item | Evidence |
|---|---|
| Branch/SHA | `main`, `8f8d4faf8ee07c9b8638a5b83a28dd8026718f05` (`git branch --show-current`, `git rev-parse HEAD`) |
| Remote parity | `origin/main` resolves to the same SHA after `git fetch origin main`; no local/remote commit divergence |
| Working tree | Pre-existing modifications/deletions in README, project file, widget, localization, DataController, views, models, shortcuts, and tests; preserved untouched |
| Tools | Xcode 26.6 (17F113); Swift 6.3.3, project Swift 5.0 |
| App target | iOS 15.0, `com.saied.sa7tot`, `Sa7tot/Sa7tot.entitlements` |
| Targets | Sa7tot, ExpenditureWidgetExtension, BudgetIntent, BudgetIntentUI, Sa7totTests |
| Schemes | Sa7tot, ExpenditureWidgetExtension, BudgetIntent, BudgetIntentUI, ConfettiSwiftUI |
| Packages | Alamofire 5.8.0; CloudKitSyncMonitor 1.2.1; ConfettiSwiftUI 1.0.1; CrookedText 0.0.1; IsScrolling 1.1.2; Popovers 1.3.2; SwiftUI-Introspect 1.3.0 |
| Build | `xcodebuild -project app/Sa7tot.xcodeproj -scheme Sa7tot -destination 'platform=iOS Simulator,id=0F7B604A-4EB1-4673-B00B-1776C8918D53' build` — **failed**, current syntax error `SettingsView.swift:397–400`, expected `)` |
| Tests | Same destination with `test` — **cancelled because build failed**; no tests executed |

Entitlements contain CloudKit `iCloud.com.saied.sa7tot`, App Group `group.com.saied.sa7tot`, ubiquity KVS, and development push on the app and widget/intent entitlements. `Info.plist` has URL types and background modes; no additional active URL/deep-link consumer was found beyond the app plist.

## Current and target architecture

```text
SwiftUI views -> @FetchRequest / DataController -> NSPersistentContainer (simulator)
                                               -> NSPersistentCloudKitContainer (device)
                                               -> App Group Main.sqlite + CloudKit + history/remote notifications
Widget/Intents -> shared DataController + same model/store
```

```text
SwiftUI -> @MainActor observable stores -> typed repositories -> Supabase client
                                                   -> Postgres/RLS (only financial authority)
                                                   <-> Realtime coordinator
Wallet/App Intents -> authenticated repository boundary (or truthful handoff to app)
UserDefaults/Keychain -> non-financial settings/session only
```

## Dependency inventory

| Current dependency / evidence | Target and use | Read/write | Persistence-specific | Action/replacement | Risk |
|---|---|---|---|---|---|
| `DataController.swift:107-173` container, store, CloudKit, history | app + all extension targets; model is in all source phases | both | yes | replace with provider/session/repositories; delete after parity | Critical |
| `DataController.swift:214-241,1893-1905` batch fetch/save/merge | app and shared targets | both | yes | repository CRUD/RPC | High |
| 43 `@FetchRequest` / `FetchedResults` sites, e.g. `NewBudgetView.swift:118-124`, `TransactionCategoryPicker.swift:7` | SwiftUI screens | read | yes | store-published arrays/async queries | High |
| 47 `NSFetchRequest` sites, e.g. DataController:561-1777 | list, budgets, search, insights, widget, export | read | yes | SQL queries/views/RPC | High |
| model versions `app/Sa7tot/Data/MainModel.xcdatamodeld`, 5 versions, current 5 | app, widget, BudgetIntent, BudgetIntentUI, tests | both/generated | yes | delete only after all targets stop compiling it | Critical |
| `WidgetKit`/`WidgetCenter` (12 imports, 11 refs; DataController:236,248,846,869) | app + ExpenditureWidgetExtension | read/refresh | indirectly | remove widget target and refresh side effects | High |
| `UserDefaults(suiteName:)` 161 occurrences | app, widget, shortcut settings/fallback IDs | both | no, but shared suite currently coupled | keep only if proven shared-settings consumer; prefer standard defaults for app-only settings; Keychain for session | Medium |
| `CloudKitSyncMonitor` package/project refs | app | read/monitor | yes | remove with CloudKit | Medium |
| App Intents `NewTransactionIntent`, `LogWalletExpenseIntent`, `BudgetInsightsIntent` | app target; direct inserts/query | both | currently yes | typed remote repository; validate execution auth/network | Critical |

No `NSManagedObject` subclasses are hand-written; generated classes come from the model. `DataController` is nevertheless directly compiled into app, widget, and intent-related targets, and `MainModel.xcdatamodeld` is compiled into app, widget, both BudgetIntent targets, and tests (`project.pbxproj:913-939,1051-1076`).

## Entity reconstruction and proposed mapping

The active model is version 5 (`project.pbxproj:1705-1715`). It contains Account, Category, Transaction, Budget, MainBudget, and TemplateTransaction. Earlier versions include TestingEntity and progressively add accounts, transfer destination, and Wallet fields; they are historical, not target tables.

| Entity/current semantics | Relevant current fields | PostgreSQL decision |
|---|---|---|
| Account | id UUID; name; typeRawValue; openingBalance Double; currencyCode; iconName; colour; walletLabel; isArchived; createdAt; order; transactions/incomingTransfers/templates | `accounts`; numeric(20,6), enum/constrained kind, UTC created_at, wallet_label retained; balance derived from opening + signed transactions |
| Category | id, name, normalized/display name, income, colour, iconIdentifier, dateCreated, order; cascades to transactions/templates | `categories`; normalized_name unique per user/income; delete should be restricted or explicitly reassign, not accidental cascade of financial history |
| Transaction | amount Double; date; duplicated day/month; id; income; note; onceRecurring; recurringType/coefficient; typeRawValue; merchant/normalizedMerchant; origin/review/wallet label/external ref/createdAt; account, destinationAccount, category | `transactions`; amount numeric, kind enum, occurred_at UTC; derive day/month in SQL using profile timezone; transfer source/destination in one row; preserve Wallet metadata |
| Budget/MainBudget | amount Double, dateCreated, green, startDate, type, optional category | one `budgets` table with `is_main`; calculate period end/spent; retain green only if UI semantics still require it |
| TemplateTransaction | amount, id, income, note, order, recurringType/coefficient, category, account | `recurring_transactions`; no generated transaction row in template; idempotent server job creates transactions |

The current `day`/`month` fields are denormalized helpers (`contents` in model v5). Remove them from the authoritative schema. All persisted amounts are Double (`Transaction.amount` and related model attributes), and Wallet parsing converts Decimal to Double at `DataController.swift:474-476`; this is unacceptable for remote financial persistence. Use Swift `Decimal`/string Codable mapping to Postgres `numeric(20,6)`. Dates are `Date`/UTC instants, but day/month are formed with a Gregorian/current calendar (`DataController.swift:416-422`), so profile timezone must govern SQL grouping and budget/recurring boundaries.

## Business rules and call graph

`NewTransactionIntent.swift:69-116` and transaction editor paths call `DataController.newTransaction` (`392-443`): trim note or use category name, set expense/income, manual origin/confirmed review, assign default account, amount/date/id, then recurrence and save. Failure deletes the unsaved object. Wallet path (`447-523`) parses amount, resolves account from App Group fallback/label, scans local transactions for duplicates, categorizes merchant, sets `needsReview` when uncertain, saves, and schedules a notification. Remote replacement must use a server uniqueness key and return a truthful error/result.

Transfers are one Core Data Transaction with source `account`, destination `destinationAccount`, and transfer type (`526-541`). Existing predicates explicitly exclude transfers from logs and budgets (`888-915`, `1358-1368`). `TransferValidationService` is the client rule boundary; the server must repeat ownership, same-account, amount, and currency checks in an atomic RPC. Do not model a transfer as two independent client inserts.

Budgets calculate `budget - sum(transaction.amount)` (`1332-1355`) with expense/non-transfer predicates. Account balances and credit-card rules are implemented in `AccountSupport.swift` and helper services and must be ported as tested pure functions before SQL views are accepted. Categories normalize names and prevent duplicate names within income/expense groups (`791-874`).

Recurring generation is app-launch/client-triggered: `updateRecurringTransactions` fetches due transactions and `updateRecurringTransaction` backfills missed dates or creates today’s occurrence (`285-371`), using day/week/month integer raw values. Recommend a scheduled Edge Function/cron plus idempotency, with client reconciliation as a fallback—not client launch as the only trigger.

Read paths include log/history (`fetchRequestForLogView`), balances/graphs, budgets, search/filter/category selection, review queue, export (`fetchRequestForExport`), and shortcut entity queries (`ShortcutsEntities.swift`). Future owners: repositories/stores for screen state; SQL views/RPC for balances, budget totals, grouped history and search; local UserDefaults only for display settings; removed feature for widgets.

## Targets, extensions, and widget removal manifest

The app target embeds `ExpenditureWidgetExtension`, `BudgetIntent`, and `BudgetIntentUI` (`project.pbxproj:186-197,1080-1094`). Widget bundle ID is `com.saied.sa7tot.widget`; Budget intent IDs are `com.saied.sa7tot.budget-intent` and `com.saied.sa7tot.budget-intent-ui`. Widget files are `app/ExpenditureWidget/*.swift`, its `Assets.xcassets`, localized `WidgetConfiguration.strings`, `Base.lproj/WidgetConfiguration.intentdefinition`, `Info.plist`, and `app/ExpenditureWidgetExtension.entitlements`; remove their target membership, target/scheme/product/embed/dependency/build-phase entries, and any app imports/refresh calls only in the implementation phase. Current widget source directly reads `DataController`/Core Data (for example `MainBudgetWidget.swift:63-75`, `BudgetWidget.swift:53-63`) and shared defaults. Do not delete them during the audit.

BudgetIntent/BudgetIntentUI are not widgets and remain candidates for migration. `BudgetIntent` Info.plist handles legacy Intents; the actual financial AppIntents execute in the app target (`NewTransactionIntent.swift:273-310`). The current App Group is still consumed by app settings, Wallet fallback, shortcut settings, and widget. Decision: **Keep temporarily**; remove after widget/Core Data/CloudKit removal and a proof that no active intent/session-sharing consumer needs it. Prefer Keychain access for auth session sharing; never store financial records or a service key in the group.

## Wallet, App Intents, and authentication

Current path is Apple Wallet Personal Automation → `LogWalletExpenseIntent` (`openAppWhenRun = false`, `NewTransactionIntent.swift:273-310`) → local DataController → local duplicate/categorization/review → Core Data save → notification. In the target architecture an extension/background intent cannot assume an authenticated Supabase session or network. Primary recommendation: Sign in with Apple through Supabase Auth, persist the refresh/session credential in Keychain, and require a real user identity so reinstall + sign-in restores the same rows. Email magic link is a viable fallback; anonymous auth fails the stated reinstall recovery requirement unless later linked. Never embed `service_role`; only public/publishable key plus authenticated session and RLS.

For logged out, offline, expired, or timeout cases, return an explicit “open Sa7tot/sign in/connect” result and do not claim an expense was saved. Server-side `(user_id, external_reference)`/fingerprint uniqueness is required for multi-device race safety. If extension session sharing cannot be proven on a physical device, hand off to the main app rather than inventing an insecure shared store.

## Repository/store and Realtime design

Use `SupabaseClientProvider` (configured client, no secrets), `AuthStore`/`SessionStore` (auth lifecycle, Keychain restore), repositories for accounts/categories/transactions/budgets/recurring/Wallet, `@MainActor` stores for observable state, and one `RealtimeCoordinator`. Stores own loading/refresh/error state; repositories are async, cancellable, and return server-confirmed values. Save flow is request → server response → store update/UI dismissal. Logout cancels tasks/channels and clears stores; auth changes rebuild the subscription set. Pagination is cursor/date based; SQL owns filtering/search/sorting for large lists.

Realtime is not initial loading. For each required table: authenticate; create one filtered channel; begin snapshot and event buffering; fetch authoritative rows; reconcile buffered events by stable UUID and updated_at/version; process INSERT/UPDATE/DELETE idempotently; on timeout/error, mark degraded and refetch after reconnect/foreground. Ensure channel is removed on logout/navigation teardown. Realtime is required for transactions/accounts/categories/budgets only if cross-device live UI is a real requirement; recurring templates may use it for editor freshness, profiles/settings do not need it. Never trust event ordering; deletes win over stale updates.

## Security and failure UX

Enable RLS on every user-owned table with `auth.uid() = user_id` for SELECT/INSERT/UPDATE/DELETE, and use composite foreign keys `(row_id,user_id)` to prevent selecting another user’s account/category/budget as a foreign reference. Numeric money, UTC timestamps, redacted logs, Keychain sessions, no client service-role key, and separate config for development/staging/production are mandatory. Plan account deletion as an authenticated cascade or explicit data-export/delete flow; verify Supabase backups and restore drills.

No-network launch shows signed-out/offline state; initial fetch failure shows retry and no success state; Realtime failure shows stale/degraded banner while REST still works; create/edit/delete failures keep the editor open or restore prior state with an Italian error; session expiry requires reauthentication; outage never queues writes silently in v1. A non-authoritative display cache is optional later and must never be treated as saved financial data.

## Core Data/CloudKit removal map

| Current component | Replacement/deletion milestone |
|---|---|
| DataController/container/context injection | repositories/stores; delete after all reads/writes and extensions pass remote tests |
| `@FetchRequest`, manual fetches, generated entity classes/model versions | stores/SQL queries; delete after path-by-path inventory is green |
| migration services, save coordinator, history/remote-change merge | server schema/RLS/RPC/Realtime; delete after server-confirmed CRUD and reconnect tests |
| CloudKit entitlements/container and `CloudKitSyncMonitor` | delete in final cleanup after target no longer uses CloudKit |
| App Group SQLite URL and widget refresh side effects | delete after widget removal and settings consumer review |
| preview/in-memory Core Data stores and Core Data tests | replace with fixtures/repository fakes; delete after mapping/unit tests |
| README Core Data/CloudKit/WidgetKit claims | update only in final documentation phase |

## Test matrix

Unit: Decimal mapping, raw enum compatibility, transfer validation, balances, budget totals, recurring dates/timezones, fingerprints, merchant categorization, repository errors, Realtime reconciliation, auth transitions. Integration: isolated Supabase project/local stack, two-user RLS, invalid foreign ownership, CRUD, atomic transfers, deletes, Realtime CRUD/reconnect, session restoration, Sign in with Apple boundary, App Intent insert, Wallet duplicate race. UI: signed-out/sign-in/loading/populated list/add-edit-delete/accounts/transfers/budgets/search/restart/reinstall recovery/offline/repeated tab switching/logout-second-user and “A never appears for B.” Physical iPhone/Apple Developer signing/real Wallet are required for Wallet and auth extension execution; network simulation is required for failure/reconnect.

## Ranked risks

1. **Critical:** current main does not build; exact error is `SettingsView.swift:397–400`.
2. **Critical:** direct financial writes exist in app/intent/widget-shared Core Data code; replacing without missing a path creates data loss or false success.
3. **Critical:** intent execution with `openAppWhenRun = false` has no proven Supabase session/network design.
4. **High:** Double persistence and local calendar fragments can cause money/timezone divergence.
5. **High:** current App Group/CloudKit/widget coupling means target removal can break active settings or intents.
6. **High:** client-only duplicate detection is not race-safe across devices.
7. **Medium:** five model versions and raw integer semantics need explicit Codable/SQL compatibility tests.
8. **Low:** package cleanup and README drift after behavior is proven.

## Mandatory decision output

Migration feasibility: **High**, conditional on baseline repair and staged proofs.

Overall migration risk: **High**.

Recommended architecture: SwiftUI → @MainActor observable stores → typed Supabase repositories → Postgres/RLS; Realtime coordinator for live domain state.

Recommended authentication: Sign in with Apple through Supabase Auth; Keychain session restoration; email magic link as fallback.

Recommended Widget action: **Remove**.

Recommended Core Data action: replace every read/write path, then delete model/generated persistence after parity.

Recommended CloudKit action: remove entitlements/container/package after remote tests and final target cleanup.

Recommended App Group action: **Keep temporarily**, remove after the widget and all shared-settings/session consumers are proven unnecessary.

Recommended Wallet strategy: server-confirmed authenticated repository; server uniqueness for duplicates; truthful handoff/error when extension lacks session/network.

Recommended Realtime strategy: authenticated single-channel-per-store, snapshot/event reconciliation, idempotent UUID handling, reconnect/foreground refetch.

Recommended first implementation phase: **Phase 0 — repair/verify baseline, then Phase 1 authenticated read-only RLS proof**.

Blocking issues before implementation: current compile failure; no Supabase project/config/auth decision; no proven extension session-sharing path; no approved schema/RLS test environment; no complete account/credit-card rule test fixture.

## Exact commands executed

`git branch --show-current`; `git rev-parse HEAD`; `git status --short --branch`; `git fetch origin main`; `git rev-parse origin/main`; `xcodebuild -list -project app/Sa7tot.xcodeproj`; `xcodebuild -showdestinations`; `xcodebuild -showBuildSettings` for all five targets; `xcodebuild ... build`; `xcodebuild ... test`; `swift --version`; `xcodebuild -version`; `rg` inventories; `plutil` entitlements/package inspection; `nl`/`xmllint` source/model inspection.

No application source, Xcode project, model, entitlement, target, dependency, or user data was modified by this audit. Only the three documentation artifacts named in the request were created.
