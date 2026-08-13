#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
release_dir=${1:-}
deploy_host=${SA7TOT_DEPLOY_HOST:-89.167.101.23}
deploy_user=${SA7TOT_DEPLOY_USER:-root}
: "${SA7TOT_DEPLOY_CONFIRM:?Set SA7TOT_DEPLOY_CONFIRM=I_UNDERSTAND_REMOTE_UPLOAD to permit a future upload}"
[[ "$SA7TOT_DEPLOY_CONFIRM" == I_UNDERSTAND_REMOTE_UPLOAD ]] || { echo "upload confirmation mismatch" >&2; exit 2; }
[[ -n "$release_dir" && -d "$release_dir" ]] || { echo "release directory is required" >&2; exit 2; }
[[ "$release_dir" == "$repo_root/.deploy/staging/sa7tot-api-"* ]] || { echo "release must be a local packaged release" >&2; exit 2; }
[[ "$deploy_host" != *[[:space:]]* && "$deploy_host" != -* && "$deploy_host" != */* ]] || { echo "invalid deploy host" >&2; exit 2; }
[[ "$deploy_user" != *[[:space:]]* && "$deploy_user" != */* ]] || { echo "invalid deploy user" >&2; exit 2; }

release_name=$(basename "$release_dir")
release_id=${release_name#sa7tot-api-}
[[ -n "$release_id" && "$release_name" == "sa7tot-api-$release_id" ]] || { echo "invalid packaged release name" >&2; exit 2; }
remote_target="$deploy_user@$deploy_host:/opt/sa7tot-api/releases/$release_id"

echo "This script is a future upload tool only; review the target before enabling it." >&2
echo "No upload was performed by the local foundation task." >&2
echo "Future target: $remote_target" >&2
