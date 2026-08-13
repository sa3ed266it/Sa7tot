#!/usr/bin/env bash
set -euo pipefail

release_root=${SA7TOT_RELEASE_ROOT:-/opt/sa7tot-api}
host_port=${SA7TOT_API_HOST_PORT:-8010}
expected_head=${SA7TOT_EXPECTED_ALEMBIC_HEAD:-0008_subscription_reminders}

[[ "$release_root" == /opt/sa7tot-api ]] || { echo "unexpected release root; refusing" >&2; exit 2; }
[[ "$host_port" =~ ^[0-9]+$ && "$host_port" -ge 1024 && "$host_port" -le 65535 ]] || { echo "invalid host port" >&2; exit 2; }
[[ -f "$release_root/shared/.env" ]] || { echo "missing shared env file" >&2; exit 1; }
[[ -L "$release_root/current" ]] || { echo "current release must be a symlink" >&2; exit 1; }
current=$(readlink -f "$release_root/current")
[[ "$current" == /opt/sa7tot-api/releases/* ]] || { echo "current points outside releases" >&2; exit 2; }
[[ -d "$current/backend" ]] || { echo "current release is incomplete" >&2; exit 1; }

if command -v ss >/dev/null 2>&1 && ss -H -ltn "sport = :$host_port" | grep -q .; then
  echo "host port $host_port is already occupied; refusing to stop or replace an unknown process" >&2
  exit 1
fi

cd "$current/backend"
compose=(docker compose --project-name sa7tot-api --env-file "$release_root/shared/.env" -f compose.production.yaml)
packaged_head=$("${compose[@]}" run --rm --no-deps api alembic heads 2>/dev/null | awk '/^[0-9a-f_]+/ {print $1}' | sort -u)
[[ "$packaged_head" == "$expected_head" ]] || { echo "packaged migration head $packaged_head does not match expected $expected_head" >&2; exit 1; }
actual=$("${compose[@]}" run --rm --no-deps api alembic current 2>/dev/null | awk '/^[0-9a-f_]+/ {print $1}' | tail -1)
[[ "$actual" == "$expected_head" ]] || { echo "database revision $actual does not match expected $expected_head" >&2; exit 1; }
echo "preflight passed: release=$current host_port=$host_port packaged_head=$packaged_head alembic=$actual"
