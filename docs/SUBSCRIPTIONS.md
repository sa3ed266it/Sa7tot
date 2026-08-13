# Sa7tot Subscriptions

This document describes the currently implemented subscription lifecycle,
backend authority, client state, and server-side renewal reminder scheduler.
Production APNs and physical reminder receipt remain separate validation gates.

## 3.1 Scope

Current implemented behavior covered here includes:

- The backend subscription data model.
- Billing-date calculation and authority.
- Request-triggered materialization.
- Idempotent subscription occurrences.
- Pause, resume, and cancellation behavior.
- iOS loading, editing, and refresh behavior.
- The boundary between subscriptions and recurrences.

Server-side subscription renewal reminders are implemented in the backend for
the approved Phase 2 Development/Sandbox flow. Physical visible receipt and
Production APNs remain separate validation gates.

## 3.2 Subscription Data Model

The backend entity is `Subscription` in
`backend/app/models/entities.py`. The API representation is
`SubscriptionOut` in `backend/app/schemas/subscriptions.py` and the iOS
representation is `RemoteSubscriptionDTO`.

Important fields are:

| Concept | Current field | Meaning |
|---|---|---|
| Identity | `id` | Subscription identifier |
| Ownership | `user_id` | Authenticated application owner |
| Account | `account_id` | Account charged by the subscription |
| Category | `category_id` | Optional category |
| Service identity | `service_id` or `custom_name` | Exactly one subscription identity is required |
| Amount | `amount_minor` | Positive integer minor-unit amount |
| Currency | `currency_code`, `currency_exponent` | Account-compatible currency representation |
| Schedule | `cadence`, `cadence_interval` | Weekly, monthly, or yearly cadence and interval |
| Anchor | `billing_anchor` | Date used as the schedule anchor/start date |
| Next renewal | `next_billing_date` | Current backend renewal/materialization date |
| Lifecycle | `status` | `active`, `paused`, or `cancelled` |
| Note | `note` | Optional user note |
| Audit timestamps | `created_at`, `updated_at` | Backend-managed timestamps |

The backend owns persisted subscription values and validates account ownership,
category ownership, identity, positive amount, cadence, status, and currency
compatibility.

## 3.3 Billing-Date Authority

`next_billing_date` is the backend-authoritative renewal date. The iOS client
renders the value returned by the API and does not independently own an
authoritative renewal schedule.

On normal client creation, `create_subscription` calculates the first
occurrence on or after the user-local current date from `billing_anchor`,
`cadence`, and `cadence_interval`. The create schema retains an optional
`next_billing_date` input for controlled initial-state, seed, and migration
flows; it is not a writable field in the update contract.

When a schedule field changes during an update, the backend recalculates the
next date from the current user-local date and the updated anchor/cadence/
interval. When an active subscription is resumed, the backend advances the
next date to the next occurrence after the user-local current date.

`next_billing_date` is read-only in `SubscriptionUpdate`. A client cannot
arbitrarily override it through PATCH. Non-schedule edits preserve the current
date, while anchor/cadence/interval edits recalculate it authoritatively.

The user-local current date comes from the profile timezone through
`get_or_create_profile` and `ZoneInfo(profile.timezone)`. Billing dates are
date-only values; this implementation does not define a notification delivery
clock time.

Authoritative paths:

- `backend/app/services/subscriptions.py`
- `backend/app/services/scheduling.py`
- `backend/app/models/entities.py`
- `backend/app/schemas/subscriptions.py`

## 3.4 Materialization

The current implemented flow is request-triggered:

```text
active subscription is due
  → POST /v1/subscriptions/materialize
  → materialize_due_subscriptions
  → subscription occurrence and transaction/movement
  → advance next_billing_date
```

The materializer:

- Uses the profile timezone to determine the current local date.
- Considers active subscriptions whose `next_billing_date` is on or before
  that date.
- Locks due subscriptions while processing them.
- Creates a `SubscriptionOccurrence` and linked transaction for each due
  scheduled date.
- Skips archived accounts.
- Rejects a subscription/account currency mismatch.
- Advances the subscription to the next occurrence.

There is no background scheduler, worker, cron job, or subscription-reminder
service implemented in the repository.

The iOS `FinancialRemoteStore` calls subscription materialization before
listing subscriptions and after subscription creation or update. The backend
endpoint is:

- `backend/app/api/v1/endpoints/subscriptions.py`

The service is:

- `backend/app/services/materialization.py`

## 3.5 Idempotency

Each subscription occurrence uses a stable key composed of the subscription ID
and scheduled date:

```text
<subscription-id>|<scheduled-date>
```

Before creating a transaction, the materializer looks up the corresponding
`SubscriptionOccurrence`. If it already has a transaction, the occurrence is
skipped. The transaction records the subscription ID and occurrence key as
well.

This prevents retries, relaunches, repeated loads, and concurrent materializer
calls from creating duplicate financial movements.

Authoritative tests include:

- `backend/tests/test_subscriptions.py`
- `backend/tests/test_recurrences.py`
- `backend/tests/test_api.py`

## 3.6 Timezone Semantics

Subscription date calculations use the profile’s stored `timezone` value. The
backend converts the current UTC time into that named timezone before deriving
the local current date. The profile default is `Europe/Rome` in the current
model configuration.

`billing_anchor` and `next_billing_date` are PostgreSQL/API date-only values.
Materialization timestamps such as `occurred_at` and `materialized_at` are
timezone-aware timestamps, while the scheduled financial day remains the
date-only occurrence date.

Recurrence materialization is separate and currently uses the explicit
`Europe/Rome` timezone constant in `backend/app/services/recurrences.py`; it
should not be silently described as having the same profile-timezone behavior
as subscriptions.

DST/reminder-time edge coverage includes the Phase 2 Europe/Rome reminder
delivery boundary. Reminder delivery remains separate from financial
materialization.

## 3.7 Subscription Status, Pause, and Cancel

The backend status values are `active`, `paused`, and `cancelled`.

- Active subscriptions are eligible for materialization.
- Paused and cancelled subscriptions are excluded from the due-materialization
  query.
- Resuming sets `next_billing_date` to the next occurrence after the user-local
  current date.
- Pausing or cancelling changes status and preserves the stored date unless a
  separate schedule change recalculates it.
- The iOS list currently shows active and paused subscriptions; cancelled rows
  are not shown in the visible list.
- Existing materialized transactions remain financial history; status changes
  do not delete them.

Reminder cancellation and rescheduling semantics are implemented by the Phase
2 backend reminder service for superseded, paused, and cancelled subscriptions.

## 3.8 iOS Subscription State

`FinancialRemoteStore` owns the remote subscription collection and mutation
flow. It uses the explicit state enum:

```text
idle → loading → loaded
                 ↘ failed
```

The store also tracks `hasLoadedSubscriptions`, an error message, and a
deduplicated in-flight subscription load task.

`SubscriptionManagerView` loads subscriptions in its task. While the first
load is pending it shows the loader; when loading fails it shows the error
state; otherwise a loaded empty result shows the empty state. Therefore an
empty subscription list is valid loaded data and is not itself used as the
loading signal.

Current mutation behavior:

- Create: remote create, account-cache invalidation, materialization, list
  refresh, and movement refresh.
- Update: remote update, affected-account cache invalidation, materialization,
  list refresh, and movement refresh.
- Pause/resume/cancel: remote status change, affected-account cache
  invalidation, and subscription-list refresh.

The client renders server-confirmed `RemoteSubscriptionDTO` values. It does
not calculate an authoritative renewal date locally.

## 3.9 Subscription Logos

Subscription logo mapping, local assets, fallback behavior, and maintenance
tooling are documented separately in [Subscription Logos](SUBSCRIPTION_LOGOS.md).

## 3.10 Relationship to Recurrences

Subscriptions and recurrences are separate backend concepts:

| Concern | Subscriptions | Recurrences |
|---|---|---|
| Entity | `Subscription` | `RecurrenceRule` |
| Schedule field | `billing_anchor`, `next_billing_date` | `anchor_date`, `next_occurrence_date` |
| Materializer | `materialize_due_subscriptions` | `materialize_due_recurrences` |
| Financial origin | `subscription` | `recurrence` |
| Cadence | weekly/monthly/yearly | daily/weekly/monthly |
| Status | active/paused/cancelled | active/paused/cancelled |

They share scheduling-style helpers and occurrence-based idempotency patterns,
but they do not represent the same product concept and must not be merged in
documentation or implementation without an explicit design change.

## 3.11 Current Invariants

| Invariant | Why it matters | Enforced by |
|---|---|---|
| Backend owns `next_billing_date` | Keeps renewal state consistent across clients | `subscriptions.py`, API DTOs, persisted entity |
| Only active subscriptions materialize | Prevents paused/cancelled items from generating new movements | `materialization.py` status query |
| Materialization is idempotent | Prevents duplicate financial movements on retries | occurrence key, occurrence row, transaction link, tests |
| Ownership derives from authenticated user | Prevents cross-user subscription/account/category access | FastAPI auth and service queries |
| Billing dates use profile timezone | Makes due-date comparison use the user’s local date | `get_or_create_profile`, `ZoneInfo(profile.timezone)` |
| Empty subscriptions can be valid loaded data | Prevents an empty account from being mistaken for a loading state | `RemoteSubscriptionLoadState`, `hasLoadedSubscriptions`, `SubscriptionManagerView` |
| Client refresh follows materialization/mutations | Keeps account movement and subscription UI server-confirmed | `FinancialRemoteStore` subscription methods |

## 3.12 Server-Side Subscription Renewal Reminders

The Phase 2 backend scheduler uses the authoritative subscription
`next_billing_date` and the owner profile's named IANA timezone. It sends one
reminder seven calendar days before renewal at 09:00 local time. A bounded
three-calendar-day catch-up window is allowed while renewal is still in the
future; a subscription created or schedule-edited inside that seven-day
window is not converted into a misleading late reminder.

The internal, hosting-provider-agnostic command is invoked hourly:

```sh
python -m app.scripts.send_subscription_reminders --environment development
```

Use `--dry-run` for safe inspection. Development/Sandbox sends require the
configured development APNs environment. Production sends require explicit
production configuration and `--allow-production`; Production APNs is not
validated in this repository.

Migration `0008_subscription_reminders` stores one logical reminder event and
one durable per-device delivery row for each active environment-matching
device. Database uniqueness, short event leases, bounded retry state, and
current subscription revalidation prevent duplicate work and stale renewal
sends. Permanent invalid-token responses deactivate only the affected device;
transient and provider-authentication failures remain retryable.

Notification copy contains the subscription name and a localized seven-day
renewal message based on the profile locale. Amounts, currency, account names,
and balances are never included. Local daily notifications remain separate;
there is no local subscription-reminder fallback and no tap/deep-link routing.

## 3.13 Open Product Decisions

| Decision | Current status | Why it matters |
|---|---|---|
| Additional reminder lead times | UNIMPLEMENTED | Phase 2 supports one seven-day reminder only |
| Reminder delivery clock time | FIXED FOR PHASE 2 | Delivery is 09:00 in the profile timezone; no user setting exists |
| User-configurable reminder time | UNDECIDED / REQUIRES PRODUCT DECISION | Determines preference storage and UI |
| Multi-device delivery policy | FIXED FOR PHASE 2 | All active devices in the selected APNs environment are targeted |
| Paused/cancelled reminder behavior | FIXED FOR PHASE 2 | Open events are cancelled and unsent deliveries expire |
| Rescheduling after edits | IMPLEMENTED FOR PHASE 2 | Superseded renewal identities are cancelled |
| Local-notification fallback | NOT PLANNED FOR PHASE 2 | Server APNs remains the subscription reminder path |
| Duplicate reminder prevention | IMPLEMENTED FOR PHASE 2 | Logical and per-device unique identities are durable |
| Notification tap destination | UNDECIDED / REQUIRES PRODUCT DECISION | Determines future deep-link/navigation behavior |

## 3.14 Source-of-Truth Paths

### Backend

- `backend/app/models/entities.py`
- `backend/app/schemas/subscriptions.py`
- `backend/app/services/subscriptions.py`
- `backend/app/services/materialization.py`
- `backend/app/services/scheduling.py`
- `backend/app/services/recurrences.py`
- `backend/app/api/v1/endpoints/subscriptions.py`
- `backend/app/api/v1/endpoints/recurrences.py`

### iOS

- `app/Sa7tot/Remote/DTO/SubscriptionDTO.swift`
- `app/Sa7tot/Remote/Repositories/SubscriptionsRepository.swift`
- `app/Sa7tot/Remote/Financial/FinancialRemoteStore.swift`
- `app/Sa7tot/Views/SubscriptionManagerView.swift`
- `app/Sa7tot/Views/RemoteFinancialViews.swift` (`RemoteSubscriptionEditorView`)

### Tests and related documentation

- `backend/tests/test_subscriptions.py`
- `backend/tests/test_recurrences.py`
- `backend/tests/test_api.py`
- `docs/ARCHITECTURE.md`
- `docs/TESTING.md`
- [Subscription Logos](SUBSCRIPTION_LOGOS.md)

Related documentation:

- [Architecture](ARCHITECTURE.md)
- [Notifications](NOTIFICATIONS.md)
- [Testing](TESTING.md)
- [Subscription Logos](SUBSCRIPTION_LOGOS.md)
