#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${NIGHTLY_LOG_HELPER:-$repo_root/modules/services/scripts/nightly-log.sh}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

state_dir="$tmpdir/state"
log_file="$state_dir/last-run.log"
mkdir -p "$state_dir"
chmod 0755 "$state_dir"
printf 'stale previous run\n' > "$log_file"
chmod 0644 "$log_file"

prepare_private_log
[[ "$(stat -c '%a' "$state_dir")" == 700 ]]
[[ "$(stat -c '%a' "$log_file")" == 600 ]]
[[ ! -s "$log_file" ]]

echo 'nightly log permissions tests passed'
