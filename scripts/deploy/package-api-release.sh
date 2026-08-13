#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
release_id=${1:-$(date -u +%Y%m%dT%H%M%SZ)}
stage_root=${2:-"$repo_root/.deploy/staging/sa7tot-api-$release_id"}

case "$release_id" in
  ''|*[!A-Za-z0-9._-]*) echo "invalid release id" >&2; exit 2 ;;
esac
if [[ "$stage_root" != "$repo_root/.deploy/staging/sa7tot-api-$release_id" ]]; then
  echo "staging path must remain under the repository .deploy/staging directory" >&2
  exit 2
fi
if [[ -e "$stage_root" ]]; then
  echo "refusing to overwrite existing staging path: $stage_root" >&2
  exit 2
fi

mkdir -p "$stage_root"
rsync -a \
  --exclude='.env' --exclude='.env.*' --exclude='*.p8' --exclude='*.pem' \
  --exclude='*.key' --exclude='*.crt' --exclude='*.cer' --exclude='secrets/' \
  --exclude='.git/' --exclude='.venv/' --exclude='venv/' \
  --exclude='__pycache__/' --exclude='*.py[cod]' \
  --exclude='.pytest_cache/' --exclude='.ruff_cache/' --exclude='.mypy_cache/' \
  --exclude='tests/' --exclude='pure_tests/' --exclude='*.log' \
  --exclude='.DS_Store' --exclude='DerivedData/' --exclude='.build/' \
  "$repo_root/backend/" "$stage_root/backend/"

printf 'release_id=%s\n' "$release_id" > "$stage_root/RELEASE"
printf 'source_commit=%s\n' "$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf 'uncommitted')" >> "$stage_root/RELEASE"
if git -C "$repo_root" diff --quiet && git -C "$repo_root" diff --cached --quiet; then
  printf 'source_worktree=clean\n' >> "$stage_root/RELEASE"
else
  printf 'source_worktree=dirty\n' >> "$stage_root/RELEASE"
fi

if find "$stage_root" -type f \( -name '.env' -o -name '.env.*' -o -name '*.p8' -o -name '*.pem' -o -name '*.key' -o -name '*.crt' -o -name '*.cer' \) -print -quit | grep -q .; then
  echo "release contains a forbidden secret file" >&2
  exit 1
fi
if find "$stage_root" -type d \( -name .git -o -name .venv -o -name tests -o -name pure_tests -o -name secrets \) -print -quit | grep -q .; then
  echo "release contains a forbidden directory" >&2
  exit 1
fi
if rg -I -l 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16}|eyJ[a-zA-Z0-9_-]{20,}' "$stage_root" >/dev/null 2>&1; then
  echo "release contains a likely secret pattern" >&2
  exit 1
fi
if rg -I -l '/Users/|/home/|/opt/sa7tot-api' "$stage_root" >/dev/null 2>&1; then
  echo "release contains a personal or server absolute path" >&2
  exit 1
fi

echo "staged release: $stage_root"
