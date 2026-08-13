# Sa7tot Push Notifications

## Current architecture

The current push foundation is an authenticated, backend-mediated APNs flow:

```text
iOS Sa7tot
  → APNs registration
  → PushTokenCoordinator
  → authenticated FastAPI endpoint
  → push_device_tokens
  → backend APNs provider
  → Apple APNs
  → device
```

The main components are:

- `app/Sa7tot/AppDelegate.swift` receives APNs registration callbacks.
- `app/Sa7tot/Remote/Push/PushTokenCoordinator.swift` waits for notification authorization, reconciles the token with the authenticated session, and performs best-effort token lifecycle updates.
- `app/Sa7tot/Remote/Repositories/PushDevicesRepository.swift` calls the authenticated push-device API.
- `backend/app/api/v1/endpoints/push.py` exposes registration and deactivation endpoints. Ownership comes from the validated JWT, not from a client-provided user ID.
- `backend/app/services/push_devices.py` implements idempotent upsert, deactivation, and active-device lookup.
- `backend/app/services/apns.py` sends provider-authenticated HTTP/2 requests to Apple APNs.
- `backend/app/scripts/send_test_push.py` is a development-only generic test-push utility. It is not a public API endpoint.

## Current status

- Push foundation: implemented.
- Remote migration `0007_push_device_tokens`: applied to the device-test database.
- Row-level security: enabled with the `push_device_tokens_owner_all` policy.
- Sandbox APNs key: created and configured locally.
- APNs topic restriction: `com.saied.sa7tot`.
- Production APNs key: not yet created.
- Real Sandbox APNs test push: accepted for one active development device; visible receipt still awaits physical-device confirmation.
- Subscription seven-day reminder scheduler: not yet implemented.
- Notification tap routing: not yet implemented.

The existing generic local daily reminder remains separate from this push foundation and is intentionally unchanged.

## Step 3B physical validation — 2026-08-13

The user confirmed that notification permission was manually enabled on the paired physical iPhone 17 Pro Max. The Development app was relaunched with the LAN development API host and authenticated successfully. The normal APNs registration path produced an authenticated `PUT /v1/push/devices` response of `200`; the resulting remote row was active, `ios`, `development`, and associated with an existing authenticated profile. The row had the current app version and a single distinct token.

A force-quit and relaunch updated that same row without creating a duplicate. The development-only test sender then attempted one Sandbox push and reported `attempted=1 sent=1 deactivated=0`, which is the APNs client success path. The device notification itself could not be visually inspected from this environment, so visible receipt remains pending user confirmation. No sign-out, account switch, production APNs setup, scheduler, or routing work was performed. No token, credential, JWT, or private-key value was recorded.

## Step 3D sign-out lifecycle fix — 2026-08-13

Physical lifecycle validation found that signing out left the current development token active. The cause was that a newly created `PushTokenCoordinator` did not restore its persisted APNs token before sign-out, while deactivation failures were also swallowed. The coordinator now restores the token from its existing local persistence, awaits the authenticated deactivation request, and prevents auth sign-out from continuing when deactivation fails. Focused tests cover ordering, persisted-token recovery, authenticated DELETE behavior, no-session behavior, and failure safety. Physical sign-out/re-sign-in validation remains pending; no lifecycle checkbox is marked complete from this code-only fix.

## Apple Developer setup

In Apple Developer:

1. Open **Certificates, Identifiers & Profiles**.
2. Open **Keys** and create an APNs key.
3. For the development key, choose **Sandbox** as the environment.
4. Choose **Topic Specific** as the key restriction.
5. Select the topic `com.saied.sa7tot`.
6. Download the `.p8` file once and store it securely outside this repository.

The environment and topic restriction cannot be changed after the key is saved. The private key can be downloaded only once, so keep a secure backup. Never copy it into the repository.

## Sandbox and production

Development/debug builds use:

```text
aps-environment = development
APNs endpoint = https://api.sandbox.push.apple.com
push_device_tokens.environment = development
```

They must use the Sandbox APNs key for the `com.saied.sa7tot` topic.

TestFlight/App Store builds use:

```text
aps-environment = production
APNs endpoint = https://api.push.apple.com
push_device_tokens.environment = production
```

A Sandbox device token must never be sent to the production APNs endpoint, and a production token must never be sent to the Sandbox endpoint. Before production delivery validation, create the production counterpart/topic-specific APNs key for `com.saied.sa7tot`; do not reuse the development environment configuration.

## Local secret management

Never commit or paste any of the following into tracked files:

- `.p8` files or private-key contents
- `backend/.env`
- Supabase service-role secrets
- database passwords
- APNs JWTs
- full APNs device tokens

Recommended local storage:

```text
$HOME/.config/sa7tot/secrets/apns/
```

Use permissions `700` for the directory and `600` for each `.p8` file. The repository ignores `backend/.env` and `*.p8`.

## Required backend variables

Configure these only in the local ignored `backend/.env` or in the deployment secret manager:

| Variable | Meaning | Development value/source | Secret? |
| --- | --- | --- | --- |
| `APNS_KEY_ID` | Apple APNs key identifier | The Apple Developer key metadata | No, but keep local configuration private |
| `APNS_TEAM_ID` | Apple Developer team identifier | The signing/developer team metadata | No, but keep local configuration private |
| `APNS_BUNDLE_ID` | APNs topic/bundle identifier | `com.saied.sa7tot` | No |
| `APNS_PRIVATE_KEY_PATH` | Absolute path to the external `.p8` file | `$HOME/.config/sa7tot/secrets/apns/AuthKey_KEYID.p8` | Path is local configuration; file is secret |
| `APNS_ENVIRONMENT` | Selects the APNs endpoint and token environment | `development` for Sandbox | No |

The backend loads the private key from `APNS_PRIVATE_KEY_PATH`. It does not require the private-key contents to be copied into the repository or into tracked documentation. Production uses the same variable names with production credentials and `APNS_ENVIRONMENT=production`.

## Database and RLS

Migration `0007_push_device_tokens` creates the `push_device_tokens` table. Important fields are:

- `user_id`: authenticated application owner.
- `token`: normalized APNs device token, unique across the table.
- `platform`: currently constrained to `ios`.
- `environment`: `development` or `production`.
- `is_active`: whether the token may receive pushes.
- `last_seen_at`, `created_at`, and `updated_at`: lifecycle timestamps.

One user may have multiple device rows. Registering the same token is idempotent. A rotated token causes the previous token to be deactivated best-effort. Permanent APNs errors such as `BadDeviceToken` and `Unregistered` are treated as deactivation candidates.

RLS is enabled on the deployed table with policy `push_device_tokens_owner_all`:

```text
user_id = sa7tot_current_user_id()
```

The authenticated FastAPI layer derives ownership from the validated JWT subject. The public client cannot select an arbitrary `user_id`. RLS prevents one user from reading, changing, or deleting another user's rows, while the privileged backend role retains the access required for registration and server-side sending.

## iOS token lifecycle

The normal lifecycle is:

```text
notification permission granted
  → registerForRemoteNotifications
  → AppDelegate receives the APNs token
  → PushTokenCoordinator stores/reconciles it
  → authenticated backend upsert
```

The coordinator also handles these orderings and events:

- If authentication is ready before the token, the token is uploaded when APNs returns it.
- If the token is ready before authentication, upload waits for a signed-in session.
- On relaunch, the persisted token is reconciled without creating a duplicate row.
- On token rotation, the previous token is deactivated best-effort before the new token is registered.
- On sign-out, the current token is deactivated before the auth session is cleared.
- On sign-in again, the current token can be reactivated for the current authenticated user.
- Token ownership is reassigned by the authenticated backend flow, never by a client-supplied user ID.

## Maintenance and troubleshooting

### No token reaches the backend

Check, in order:

1. iOS notification permission is authorized.
2. The build contains the expected `aps-environment` entitlement.
3. The physical device build is signed for the correct team and bundle ID.
4. `registerForRemoteNotifications` is reached.
5. The device can reach the configured API host.
6. The authenticated session is valid.
7. Migration `0007_push_device_tokens` is applied.

### APNs returns `BadDeviceToken`

Check Sandbox-versus-Production alignment, the APNs topic, the signing entitlement, and whether the token is stale. A development token must use the Sandbox endpoint.

### APNs returns `Unregistered`

This is an expected permanent response for a no-longer-valid token. Mark the device row inactive and allow a later registration callback to create/reactivate the current token.

### Push works in Debug but not TestFlight

Check the production APNs key, production endpoint, production `push_device_tokens.environment`, and the Release signing entitlement.

### A user receives another user's notification

Treat this as critical. Check sign-out deactivation, token reassociation, JWT-derived ownership, the RLS policy, and backend authentication. Do not work around it in the client.

## Step 3 validation checklist

- [x] Migration `0007_push_device_tokens` is applied.
- [x] APNs credentials load without exposing their values.
- [x] Physical iPhone notification permission is authorized.
- [x] APNs returns a device token.
- [x] The authenticated token row is created.
- [x] Relaunch does not create a duplicate row.
- [x] One generic development test push is accepted by Sandbox APNs.
- [ ] One generic development test push is visibly received on the physical device.
- [ ] Foreground and background behavior is recorded.
- [ ] Sign-out deactivates the token association.
- [ ] Sign-in reactivates/reassociates it safely.
- [ ] No secret or full token is exposed.

## Future roadmap

- **Phase 2:** server-side seven-day subscription reminder scheduler.
- **Phase 3:** notification tap routing to **Abbonamenti** and a specific subscription.
- **Later:** production APNs credentials, delivery/retry observability, and optional additional reminder lead times.

No scheduler, worker, reminder copy, or routing is part of the current push foundation.

## Subscription reminder decision

Sa7tot intentionally chose a push-first architecture rather than a local-first scheduler for subscription reminders. The backend owns the authoritative `next_billing_date`, can react even when the app has not been reopened, and provides consistent behavior across the user's devices. This avoids replacing a local-only scheduling architecture later.

The legacy generic local daily reminder remains separate and will be migrated or retired deliberately in a future task. It is not part of the subscription reminder system yet.
