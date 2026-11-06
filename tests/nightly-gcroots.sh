#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${NIGHTLY_GCROOTS_HELPER:-$repo_root/modules/services/scripts/nightly-gcroots.sh}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
add_summary() { summary+="$1"$'\n'; }

gcroots_dir="$tmpdir/roots"
tmp_gcroots="$gcroots_dir/.staging.current"
mkdir -p "$tmp_gcroots"
ln -s /nix/store/new-srv "$tmp_gcroots/host-junixsrv"
ln -s /nix/store/old-srv "$gcroots_dir/host-junixsrv"
ln -s /nix/store/old-removed "$gcroots_dir/host-removed"
hosts=(junixsrv)
activation_deferred=1
summary=""
finalize_gcroots
[[ "$(readlink "$gcroots_dir/host-junixsrv")" == /nix/store/old-srv ]]
[[ -L "$tmp_gcroots/host-junixsrv" ]]

activation_deferred=0
finalize_gcroots
[[ "$(readlink "$gcroots_dir/host-junixsrv")" == /nix/store/new-srv ]]
[[ ! -L "$gcroots_dir/host-removed" ]]
[[ -z "$tmp_gcroots" ]]

# A partial promotion fails the run without removing the remaining old roots.
tmp_gcroots="$gcroots_dir/.staging.partial"
mkdir -p "$tmp_gcroots" "$gcroots_dir/host-z" # directory obstructs replacement
ln -s /nix/store/new-a "$tmp_gcroots/host-a"
ln -s /nix/store/new-z "$tmp_gcroots/host-z"
ln -s /nix/store/old-b "$gcroots_dir/host-b"
hosts=(a z)
if finalize_gcroots 2>/dev/null; then
  echo 'expected promotion failure' >&2
  exit 1
fi
[[ -L "$gcroots_dir/host-a" ]]
[[ -L "$gcroots_dir/host-b" ]]
[[ -L "$tmp_gcroots/host-z" ]]

# Cleanup removes our stale staging but retains pre-existing transaction data.
mkdir -p "$gcroots_dir/.staging.legacy/.previous"
ln -s /nix/store/old "$gcroots_dir/.staging.legacy/.previous/host-old"
cleanup_stale_gcroot_staging 2>"$tmpdir/warning"
[[ ! -e "$gcroots_dir/.staging.partial" ]]
[[ -L "$gcroots_dir/.staging.legacy/.previous/host-old" ]]
grep -Fq 'retaining old GC-root transaction' "$tmpdir/warning"

echo 'nightly gcroot tests passed'
