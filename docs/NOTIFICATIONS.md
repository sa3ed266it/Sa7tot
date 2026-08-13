# Sa7tot Notifications

Sa7tot currently contains two separate notification systems. The existing
local daily reminder is not the APNs push foundation and has not been replaced
by it.

## 4.1 Notification Systems Overview

| Concern | Local Daily Notification | Server APNs Push |
|---|---|---|
| Scheduled by | iOS app through `UNUserNotificationCenter` | Backend APNs provider after server-side device registration |
| Requires backend | No for scheduling/delivery after the request is accepted | Yes, for device storage and sending |
| Works if app is not reopened | A repeating local request can be delivered by iOS after it is scheduled; changes require the app | Designed to send while the app is not open, subject to APNs/device state |
| Current purpose | Existing generic daily reminder | Authenticated device registration plus server-side subscription renewal reminders |
| Current validation | Existing local implementation; permission behavior is app-driven | Development/Sandbox physically validated end-to-end |
| Production status | Existing local path remains separate | Production APNs is not configured or validated |

The Phase 2 server-side subscription reminder path is implemented for
Development/Sandbox. Local daily reminders remain separate and unchanged.

## 4.2 Local Daily Notification — Current Behavior

The local scheduler is `newNotification()` in:

```text
app/Sa7tot/Utilities/NotificationSupport.swift
```

Its current flow is:

```text
Settings notification enablement
  → removeAllPendingNotificationRequests()
  → create localized repeating calendar request
  → UNUserNotificationCenter.add(request)
```

The request:

- Uses localized title and subtitle keys.
- Uses the default notification sound.
- Uses a repeating `UNCalendarNotificationTrigger`.
- Schedules 08:00 when `notificationOption == 1`.
- Schedules 20:00 when `notificationOption == 2`.
- Otherwise reads `customHour` and `customMinute`, defaulting to 08:00.
- Uses a random UUID request identifier.
- Removes all pending requests before adding the new request.

The local scheduler reads these values from the App Group `UserDefaults` suite:

- `notificationOption` — initialized to `1` on first launch and read by the
  scheduler.
- `customHour` and `customMinute` — read by the scheduler when the option is
  not 1 or 2.

The current source search finds no active Settings control that writes
`notificationOption`, `customHour`, or `customMinute`. They are stored/read
preferences without an active visible configuration UI in the current app.

`showNotifications` and `notificationsEnabled` are maintained separately by
the app/settings layer. `newNotification()` itself selects its time from
`notificationOption`/custom values rather than directly reading those two
Boolean flags.

## 4.3 Local Permission UI

The notification row is implemented in:

```text
app/Sa7tot/Views/Settings/SettingsView.swift
```

Current behavior:

- The toggle reflects the stored `showNotifications` preference while also
  hiding the enabled state when the OS authorization status is `.denied`.
- Enabling while `.notDetermined` requests alert, badge, and sound permission.
- If authorization succeeds, the app stores the enabled flags, asks the push
  coordinator to register if authorized, and schedules the local daily request.
- If permission is denied, the stored enabled flags are cleared and an alert
  offers to open the iOS Settings app.
- If permission is already authorized, provisional, or ephemeral, enabling
  schedules the local request without requesting authorization again.
- Disabling clears both stored flags and removes all pending local requests.
- On permission refresh, a denied OS state clears the stored flags and pending
  local requests.

`ContentView` also checks for a denied permission state during app lifecycle
handling and clears the local notification preference/request when needed.

OS notification permission and APNs device-token registration are related but
different concerns. Permission controls whether registration/scheduling is
allowed; it does not itself prove that an APNs token exists or that the token
has been uploaded to FastAPI.

## 4.4 APNs Push Architecture

The server push foundation is:

```text
iOS authorization/registration
  → AppDelegate callback
  → PushTokenCoordinator
  → authenticated PUT /v1/push/devices
  → push_device_tokens
  → backend APNs client
  → Apple APNs
```

Important paths:

- `app/Sa7tot/AppDelegate.swift`
- `app/Sa7tot/Remote/Push/PushTokenCoordinator.swift`
- `backend/app/api/v1/endpoints/push.py`
- `backend/app/services/push_devices.py`
- `backend/app/services/apns.py`
- `backend/alembic/versions/0007_push_device_tokens.py`

See [Push Notifications](push-notifications/README.md) for detailed provider
setup and validation. This document intentionally does not duplicate private
credential instructions.

## 4.5 Push Device Lifecycle

Current source and physical validation establish these invariants:

- The APNs token is persisted locally so a coordinator can restore it.
- Registration and deactivation use the authenticated backend identity.
- Re-registration of the same logical token is idempotent.
- Sign-out deactivates the current device association before clearing the
  auth/session state.
- If deactivation fails, sign-out does not clear the session.
- Sign-in can reactivate/reassociate the same logical token.
- Development and production tokens are separated by environment.
- Permanent APNs errors are treated as deactivation candidates.

No token value is part of this documentation.

## 4.6 Development versus Production APNs

### Development

```text
aps-environment = development
push_device_tokens.environment = development
https://api.sandbox.push.apple.com
```

The Development/Sandbox registration, send, visible background receipt,
sign-out deactivation, sign-in reassociation, duplicate check, and final push
receipt have been physically validated.

### Production

```text
aps-environment = production
push_device_tokens.environment = production
https://api.push.apple.com
```

Production APNs credentials, signing, token registration, provider
configuration, and delivery validation are not complete.

## 4.7 Foreground versus Background Presentation

Visible background notification receipt is physically validated for the
Development/Sandbox path.

Foreground banner presentation is not currently proven by the push-foundation
validation. The current source does not provide a demonstrated
`UNUserNotificationCenterDelegate` `willPresent` implementation for foreground
presentation. Do not infer foreground banner behavior from a background
receipt.

## 4.8 Notification Tap Routing

Subscription-specific notification tap routing and deep linking are not
implemented. The current push foundation does not establish a route to
Abbonamenti or a particular subscription.

No future destination should be treated as implemented until an explicit
notification delegate/deep-link flow exists and is runtime-tested.

## 4.9 Subscription Reminder Scheduler

The internal backend command is invoked hourly by an external scheduler:

```text
hourly invocation
  → python -m app.scripts.send_subscription_reminders
  → backend-owned eligibility and profile timezone
  → durable logical event and per-device delivery rows
  → independent APNs sends
```

Phase 2 sends one reminder seven calendar days before `next_billing_date` at
09:00 in the profile's IANA timezone. It allows a three-calendar-day catch-up
window while renewal is still future, but skips a subscription created or
schedule-edited inside the seven-day window. Paused/cancelled subscriptions
are excluded, superseded renewal identities are cancelled, and no local
fallback is used.

Migration `0008_subscription_reminders` provides durable uniqueness and
short-lived claiming. All active iOS devices matching the selected APNs
environment are targeted independently. The payload contains only the
subscription name, localized seven-day copy, and non-sensitive future-ready
identifiers; no amount, currency, account, or balance is sent.

## 4.10 Multi-Device Semantics

The `push_device_tokens` table has a globally unique normalized token, but its
user index allows a user to have multiple device rows. Each row contains:

- Authenticated `user_id` ownership.
- `platform` constrained to iOS.
- `environment` constrained to development or production.
- `is_active` lifecycle state.
- App version and lifecycle timestamps.

The backend exposes active tokens for a user and optional environment filter.
Phase 2 subscription reminders target all active iOS devices in the selected
environment. Already-sent device rows are not resent; newly active devices
may be added while an eligible logical event remains open.

## 4.11 Security and Privacy

- Never log or expose a full APNs device token.
- Never expose JWTs, APNs credentials, private keys, database passwords, or
  Supabase service-role secrets.
- Device ownership comes from the authenticated backend identity, not a
  client-selected user ID.
- RLS is defense-in-depth for ordinary/direct roles; FastAPI ownership checks
  remain mandatory because privileged backend access may bypass ordinary RLS.

See [Operations](OPERATIONS.md), [Authentication Foundation](AUTHENTICATION_FOUNDATION.md),
and [Push Notifications](push-notifications/README.md).

## 4.12 Current Status Matrix

| Capability | Status |
|---|---|
| Local daily reminders | IMPLEMENTED |
| Local notification permission UI | IMPLEMENTED |
| Development APNs registration | VALIDATED |
| Development APNs delivery | VALIDATED |
| Physical sign-out lifecycle | VALIDATED |
| Production APNs | NOT IMPLEMENTED / NOT VALIDATED |
| Subscription reminder scheduler | IMPLEMENTED — Development/Sandbox code-complete |
| 7-day reminder policy | IMPLEMENTED — 7 calendar days, 09:00 local |
| Subscription-specific payload | IMPLEMENTED — privacy-conscious, localized |
| Foreground presentation | NOT VALIDATED |
| Tap routing/deep link | NOT IMPLEMENTED |
| Production retry/observability | NOT IMPLEMENTED |

## 4.13 Source-of-Truth Paths

### Local notifications

- `app/Sa7tot/Utilities/NotificationSupport.swift`
- `app/Sa7tot/ContentView.swift`
- `app/Sa7tot/Views/Settings/SettingsView.swift`

### APNs push

- `app/Sa7tot/AppDelegate.swift`
- `app/Sa7tot/Remote/Push/PushTokenCoordinator.swift`
- `backend/app/api/v1/endpoints/push.py`
- `backend/app/services/push_devices.py`
- `backend/app/services/apns.py`
- `backend/alembic/versions/0007_push_device_tokens.py`
- `backend/tests/test_push.py`
- `backend/pure_tests/test_apns.py`

### Related documentation

- [Subscriptions](SUBSCRIPTIONS.md)
- [Architecture](ARCHITECTURE.md)
- [Authentication Foundation](AUTHENTICATION_FOUNDATION.md)
- [Operations](OPERATIONS.md)
- [Testing](TESTING.md)
- [Push Notifications](push-notifications/README.md)
