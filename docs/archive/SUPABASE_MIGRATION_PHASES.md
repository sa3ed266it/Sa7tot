# Sa7tot Supabase Direct-Remote Migration Phases

This is a planning document only. No production migration or legacy-user migration is proposed because the brief states there are no production users.

## Phase 0 — Baseline and foundation

Objective: freeze the verified starting point, preserve current behavior, and resolve the existing compiler failure before architectural work. Likely files: `app/Sa7tot.xcodeproj`, configuration files, and new Supabase configuration only in a later implementation. Prerequisite: audit accepted. Acceptance: main is clean or changes are classified, app and tests build, package graph is reproducible. Tests: baseline build/test. Rollback: no source changes. Risk: Critical because current build is already failing. Out of scope: persistence rewrite.

## Phase 1 — Auth shell and remote read-only proof

Objective: add a publishable Supabase client, AuthStore/SessionStore, Sign in with Apple, and a read-only authenticated profile/accounts prototype. Acceptance: signed-out launch is safe; sign-in restores the same user after reinstall; RLS blocks a second user. Tests: auth transitions, session restoration, two-user RLS isolation. Rollback: remove the prototype behind a feature flag. Out of scope: financial writes and Core Data removal.

## Phase 2 — Codable domain and repositories

Objective: define Decimal-backed Codable models and repositories for accounts, categories, transactions, budgets, and recurring templates. Acceptance: mapping tests cover all current raw values and nullability; repositories expose typed errors and never report success before server confirmation. Tests: mapping, decimal conversion, ownership errors. Out of scope: UI-wide rewrite.

## Phase 3 — Accounts, categories, transactions

Objective: replace reads and confirmed CRUD for the core screens using observable stores. Acceptance: initial state is server state; create/edit/delete reflects only after a successful response; reinstall recovers data. Tests: CRUD, balances, filters, search, restart. Rollback: keep old screens until parity. Out of scope: transfers and recurring automation.

## Phase 4 — Realtime

Objective: add one authenticated Realtime coordinator with snapshot/subscription reconciliation. Acceptance: no missed, duplicate, stale, or cross-user rows; reconnect and foreground refetch work. Tests: INSERT/UPDATE/DELETE, reconnect, repeated navigation, logout/login. Out of scope: offline write queue.

## Phase 5 — Transfers and financial integrity

Objective: introduce the atomic `create_transfer`/update/delete RPC design. Acceptance: source/destination ownership, same-account and cross-currency rules, balances, and totals are correct under concurrent calls. Tests: atomicity and race tests. Rollback: disable transfer UI while repositories remain read-only. Out of scope: legacy data migration.

## Phase 6 — Budgets and recurring transactions

Objective: move budget calculations to SQL/RPC and choose a server-side recurring strategy. Recommendation: keep templates in Postgres and use a scheduled Edge Function/cron with an idempotency key; client launch may reconcile missed occurrences but must not be the only trigger. Acceptance: timezone-aware periods, transfer exclusion, duplicate prevention. Tests: date advancement, job retries, duplicate fingerprints. Out of scope: offline-first conflict resolution.

## Phase 7 — Wallet and App Intents

Objective: preserve Wallet/Shortcuts behavior through a shared remote repository only after authentication/session access is proven in the executing extension. Recommendation: keep intents in the main app target where possible; if extension execution is required, use a shared Keychain access group for the user session, never an App Group database or service key. Acceptance: logged-out/offline/error results are truthful and duplicate prevention is server-side. Tests: direct insert, two-device duplicate race, physical Wallet. Out of scope: Widget migration.

## Phase 8 — Settings, import/export, parity

Objective: migrate remaining read paths, settings counts, merchant review, import/export, search, and App Intents. Acceptance: Italian UI behavior and app lock remain intact; no financial data is persisted locally. Tests: UI smoke and reinstall scenario. Out of scope: Statistics revival.

## Phase 9 — Remove Widget, Core Data, CloudKit

Objective: remove WidgetKit target/files/assets/manifest and then, only after all read/write paths pass against Supabase, remove Core Data model/container, CloudKit package/entitlements, persistence helpers, and App Group-only settings. Acceptance: only the app and required intent targets remain; no forbidden symbols/imports; clean build. Rollback: revert the cleanup commit. Tests: full matrix. Out of scope: production migration.

## Phase 10 — Hardening and release gate

Objective: security review, backups, logging redaction, RLS regression suite, and documentation. Acceptance: no service-role key in client, RLS/foreign-key tests pass, outage UX is truthful, and release signing is verified on device. Out of scope: speculative offline queue.

Every phase must land as a small reviewable checkpoint with its acceptance tests green before the next phase begins.
