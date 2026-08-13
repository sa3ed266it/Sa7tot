# Sa7tot Documentation

This is the canonical index for current Sa7tot documentation. Runtime source,
project configuration, migrations, and tests remain authoritative.

## 4.1 Start Here

- [Project README](../README.md) — product overview, setup, and current scope.
- [Architecture](ARCHITECTURE.md) — current system boundaries, ownership, and invariants.
- [Development](DEVELOPMENT.md) — local backend, iOS, simulator, and device workflows.

## 4.2 Core Architecture / Authentication

- [Architecture](ARCHITECTURE.md) — remote-only financial architecture and lifecycle boundaries.
- [Authentication Foundation](AUTHENTICATION_FOUNDATION.md) — Sign in with Apple, Supabase Auth, Keychain, bearer tokens, and bootstrap readiness.

## 4.3 Backend / Operations / Release / Testing

- [Development](DEVELOPMENT.md) — development environment and validation commands.
- [Operations](OPERATIONS.md) — backend, migration, ownership, APNs, and operational boundaries.
- [Deployment Foundation](deployment/README.md) — local-only Docker, Compose, release, Nginx, and systemd templates.
- [Release](RELEASE.md) — version, signing, release-readiness, and known gates.
- [Testing](TESTING.md) — backend, iOS, localization, APNs, and runtime validation coverage.
- [Backend README](../backend/README.md) — backend setup, migrations, staging checks, and isolated tests.

## 4.4 Subscriptions / Notifications

- [Subscriptions](SUBSCRIPTIONS.md) — backend-owned renewal dates, materialization, client state, and server-side reminder delivery.
- [Notifications](NOTIFICATIONS.md) — overview of local notifications and server APNs push.
- [Push Notifications](push-notifications/README.md) — detailed APNs implementation and setup/validation record.
- [Subscription Logos](SUBSCRIPTION_LOGOS.md) — local logo catalog and maintenance tooling.

`NOTIFICATIONS.md` is the system overview. The dedicated push-notifications
README is the detailed APNs implementation and setup reference.

## 4.5 Historical Documentation

- [Archive](archive/) — historical audits, migration plans, and schema drafts.

Archive documents are historical context only. They are not current
implementation authority and must not be used to describe the active
architecture.

## 4.6 Current Status / Known Gaps

- Production APNs is incomplete.
- The subscription reminder scheduler is implemented and physically validated for Development/Sandbox, including idempotent repeat-run behavior.
- A local-only production Docker/Compose deployment foundation exists; nothing has been deployed to a VPS.
- The authoritative future Sa7tot VPS is `root@89.167.101.23`; deployment remains local-only and undeployed.
- Notification tap routing is not implemented.
- The localization integrity checker passes.

## 4.7 Documentation Maintenance Rules

- Source, project configuration, tests, and migrations are authoritative.
- Update documentation for security-sensitive lifecycle changes.
- Update documentation for schema, environment, signing, or APNs changes.
- Prefer one detailed authoritative explanation and cross-links over duplicated long sections.
- Keep future or undecided product behavior explicitly marked as such.

## Current Documentation Tree

```text
docs/
├── README.md
├── ARCHITECTURE.md
├── AUTHENTICATION_FOUNDATION.md
├── DEVELOPMENT.md
├── OPERATIONS.md
├── RELEASE.md
├── TESTING.md
├── SUBSCRIPTIONS.md
├── NOTIFICATIONS.md
├── SUBSCRIPTION_LOGOS.md
├── push-notifications/
│   └── README.md
└── archive/
```
