# Sa7tot Release Readiness

This is a repeatable release-readiness checklist. It documents current source
facts and separates Development validation from future Production work.

## 4.1 Versioning

The authoritative app version settings are in:

```text
app/Sa7tot.xcodeproj/project.pbxproj
```

The main Sa7tot target currently uses:

```text
MARKETING_VERSION = 1.0.0
CURRENT_PROJECT_VERSION = 1
```

The expected app version is therefore:

```text
1.0.0 (1)
```

`MARKETING_VERSION` is the public app version. `CURRENT_PROJECT_VERSION` is the
build identifier used to distinguish distributed builds and must be increased
appropriately for later distribution builds.

The repository has not adopted an additional semantic-versioning policy beyond
these Xcode settings.

## 4.2 Bundle and Signing Identity

The main bundle identifier is:

```text
com.saied.sa7tot
```

The app requires these capabilities/configuration areas:

- Sign in with Apple.
- APNs/Push Notifications entitlement.

Do not place Team IDs, Key IDs, certificates, private keys, or provider
credentials in documentation or source control.

## 4.3 Development versus Release/Distribution

### Current Development path

- Development Xcode configuration.
- `aps-environment = development` for the validated physical-device build.
- Development token rows.
- Sandbox APNs endpoint.
- LAN API URL when testing against a Mac-hosted backend.

### Future Release path

- Release/TestFlight/App Store distribution signing.
- Production APNs entitlement and production token rows.
- Production APNs endpoint/provider configuration.
- Distribution-build registration and receipt validation.

The checked-in APNs entitlement is development-oriented, and the project’s
Release setting alone is not proof of production APNs readiness. Production
APNs must be configured and validated separately.

## 4.4 Build Number Discipline

Every distributed TestFlight or App Store build must use an appropriate unique
and incremented build number. App Store Connect rules and the app’s distribution
history determine whether a particular number is available; the repository
does not make assumptions about that external history.

## 4.5 Pre-Release Repository Checks

Before creating a release candidate:

```sh
git status --short
git diff --check
```

Also verify:

- No tracked `.env` or `.p8` files.
- No credentials, JWTs, private keys, database passwords, or full APNs tokens
  in the diff.
- Main bundle ID and version/build metadata.
- Entitlements for the intended build configuration.
- Current Alembic revision and pending migrations.
- Localization checker status.
- Backend test status.
- iOS build and XCTest status.

The full simulator XCTest target resolves the `Sa7tot` module and the current
Debug simulator suite completes successfully. Release readiness still
requires the broader distribution and runtime checks listed below.

## 4.6 Database Compatibility

Before releasing an app/backend combination:

1. Review pending Alembic migrations.
2. Confirm the deployed backend schema is compatible with the backend binary.
3. Apply the required migration using the approved operational procedure.
4. Verify `alembic current` and `alembic check`.

The repository does not implement a zero-downtime migration strategy. Do not
assume one.

## 4.7 Push Release Readiness

### Current Development proof

- [x] Development device registration validated.
- [x] Authenticated device upload validated.
- [x] Sandbox APNs send validated.
- [x] Visible physical-device receipt validated.
- [x] Sign-out deactivation validated.
- [x] Sign-in reassociation validated.
- [x] No duplicate active token validated.

### Production requirements

- [ ] Production APNs credentials created and secured.
- [ ] Release entitlement verified as production.
- [ ] Production token registration verified.
- [ ] Production endpoint/provider configuration verified.
- [ ] Distribution-build receipt test completed.
- [ ] Development and production token environments separated.
- [ ] Safe production logging and delivery observability defined.

See [Push Notifications](push-notifications/README.md) for the current
Development/Sandbox record.

## 4.8 Authentication Release Readiness

- [ ] Sign in with Apple entitlement and provider configuration verified for
  the intended distribution environment.
- [ ] Supabase Auth configuration verified.
- [ ] Required Apple bundle/service identifiers verified without exposing
  credentials.
- [ ] Session restoration verified.
- [ ] Backend JWT signature, issuer, audience, expiration, and subject checks
  verified.
- [ ] Sign-out push deactivation completes before session clear.
- [ ] Deactivation failure prevents auth/session clear.

## 4.9 Localization Release Readiness

Run:

```sh
python3 scripts/check_localization.py
```

Verify Italian/English parity, placeholder compatibility, referenced-key
resolution, and absence of malformed empty keys.

Current worktree status: the localization integrity checker passes.

## 4.10 Testing Release Gate

See [Testing](TESTING.md) for the detailed inventory and runtime matrix.

Build success proves compilation only. It does not prove runtime UI behavior,
auth transitions, background delivery, or APNs receipt. Physical-device tests
are required for APNs lifecycle behavior.

## 4.11 Release Checklist

### Source and configuration

- [ ] Worktree reviewed and intended changes isolated.
- [ ] `git diff --check` passes.
- [ ] Version/build and bundle ID verified from the built product.
- [ ] No secrets are tracked or exposed.

### Backend and database

- [ ] Backend tests pass in an isolated test environment.
- [ ] Pending migrations reviewed.
- [ ] Deployed schema compatibility verified.
- [ ] Approved backup/recovery procedure available.

### iOS build and signing

- [ ] Intended Release/Development configuration selected.
- [ ] Sign in with Apple capability verified.
- [ ] APNs entitlement matches the intended environment.
- [ ] Distribution build metadata verified.

### Authentication

- [ ] Sign in with Apple succeeds.
- [ ] Supabase session restoration succeeds.
- [ ] Authenticated bootstrap succeeds.
- [ ] Sign-out and push-token lifecycle succeeds.

### Notifications

- [x] Development/Sandbox physical push lifecycle validated.
- [ ] Production APNs configured and validated.
- [ ] Notification tap routing implemented and validated.
- [ ] Subscription reminder scheduler physically validated on Development/Sandbox.

### Localization

- [ ] Localization checker passes.
- [ ] Italian and English visual QA passes.

### Testing and security

- [ ] Backend tests pass.
- [ ] iOS build passes.
- [x] XCTest target is healthy for the current Debug simulator configuration.
- [ ] Physical-device critical-path smoke test passes.
- [ ] Secret/redaction review passes.

### Distribution and post-release

- [ ] External distribution metadata is available and approved.
- [ ] Production health and error monitoring is available.
- [ ] Post-release auth, bootstrap, financial API, and notification checks are
  assigned and recorded.

## 4.12 Post-Release Validation

Verify, in the intended environment:

- App launch and authentication.
- Session restoration.
- `/v1/bootstrap` and critical financial API requests.
- Database compatibility and backend health.
- Push registration and notification receipt.
- Error rates and operational logs where observability exists.

Production monitoring, alerting, and ownership are not currently defined in
the repository.

## 4.13 Backend Deployment Foundation

The repository contains a local-only production packaging foundation for the
FastAPI backend:

- Authoritative future host: `root@89.167.101.23`.
- Sa7tot release root: `/opt/sa7tot-api`.
- Sa7tot Compose project: `sa7tot-api`.
- Host API binding: `127.0.0.1:8010`.

- `backend/Dockerfile` builds a minimal non-root API image.
- `backend/compose.production.yaml` uses the independent `sa7tot-api`
  Compose project and binds the API to `127.0.0.1:8010` by default.
- `scripts/deploy/package-api-release.sh` creates an inspected immutable
  release candidate without environment files, APNs keys, tests, or local
  developer artifacts.
- `scripts/deploy/api-production-preflight.sh` is a guarded future-server
  check for the release symlink, port conflict, and expected Alembic head.
- `scripts/deploy/sa7tot-reminders.service` and `.timer` are templates only;
  they have not been installed or enabled.

Nothing in this repository performs a remote upload or deployment. A future
VPS must provide the shared environment file and APNs private key externally;
Production APNs, DNS, TLS, Nginx installation, and the production database
remain separate operator-controlled steps.

The future first-deployment connection is `ssh root@89.167.101.23`; the
future release destination is
`root@89.167.101.23:/opt/sa7tot-api/releases/<release-id>`. The API hostname
remains undecided, so the Nginx template continues to use its placeholder.

### Future rollback and retention

Keep the active release and at least the immediately previous immutable
release. A rollback must select a known previous release, validate both live
and ready health endpoints, and only then switch the `current` symlink. An
application rollback does not roll back database migrations, so schema
compatibility must be checked before changing the active release. Older
releases must be removed only by an explicit exact path after confirming it is
neither the active nor the previous release; never use an unchecked wildcard
under `/opt/sa7tot-api`.
