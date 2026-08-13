# Sa7tot Deployment Foundation

This directory contains reviewed templates for a future Linux VPS deployment.
It is local implementation only: nothing here has been installed on a server,
and no SSH, DNS, TLS, production database, or Production APNs action is part
of the current work.

## Authoritative target

- Production host: `root@89.167.101.23`
- Sa7tot release root: `/opt/sa7tot-api`
- Compose project: `sa7tot-api`
- Local API binding: `127.0.0.1:8010` → container port `8000`
- Future API hostname: not chosen; the Nginx file retains the placeholder
  `api.example.com`.

This VPS also hosts Patente_Facile, but Sa7tot uses its own Compose project,
release tree, localhost port, shared secrets, Nginx site, and reminder units.
Sa7tot tooling must never reuse Patente_Facile files or touch its containers.

## Current status

- Production Docker image: defined; runtime build is pending Docker installation
  on the local workstation.
- Compose project: isolated as `sa7tot-api`, with the default host binding
  `127.0.0.1:8010 -> 8000`.
- PostgreSQL: external Supabase/PostgreSQL; no database container.
- Secrets: supplied through an external env file and read-only APNs key mount.
- Production APNs: **NOT CONFIGURED / NOT VALIDATED**.
- Nginx and TLS: example only; not installed.
- Reminder systemd service/timer: template only; not installed or enabled.

## Local validation

From the repository root:

```sh
docker build -f backend/Dockerfile backend
SA7TOT_API_ENV_FILE=/path/to/safe/env \
SA7TOT_APNS_PRIVATE_KEY_FILE=/path/to/safe/placeholder.p8 \
  docker compose -f backend/compose.production.yaml config
scripts/deploy/package-api-release.sh
```

The env file and key path above are examples. Do not use real Production APNs
credentials for local validation. The package script creates a new local
`.deploy/staging/` candidate and refuses to overwrite one.

## Future release layout

```text
/opt/sa7tot-api/
├── releases/<release-id>/
├── shared/.env
├── shared/apns-private-key.p8
└── current -> releases/<release-id>
```

An operator must verify the host port is free, compare the database revision
with the packaged Alembic head, apply reviewed migrations as a separate
explicit step, start the candidate, verify `/health/live` and `/health/ready`,
and only then activate the release. Application rollback never performs a
database downgrade.

## Future sequence

1. Provision the isolated server directories.
2. Install the production env file and APNs key with restrictive permissions.
3. Choose and preflight the localhost host port.
4. Configure the real domain and DNS.
5. Install the Nginx site and obtain TLS certificates.
6. Apply and verify database migrations through the guarded process.
7. Deploy an immutable API release and validate health.
8. Install and enable the hourly reminder timer.
9. Configure and separately validate Production APNs.
10. Perform TestFlight/production physical validation.

`upload-api-release.sh` is intentionally defensive and was not run. No
server-side action is implied by these templates. The future first-deploy
connection target is:

```sh
ssh root@89.167.101.23
```

The future upload destination is
`root@89.167.101.23:/opt/sa7tot-api/releases/<release-id>`. The shared
`/opt/sa7tot-api/shared/.env` and
`/opt/sa7tot-api/shared/apns-private-key.p8` are provisioned only on the server
later and are never stored in this repository.
