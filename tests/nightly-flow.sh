#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin"
printf '#!%s\n' "$BASH" > "$tmpdir/bin/curl"
cat >> "$tmpdir/bin/curl" <<'CURL_STUB'
set -euo pipefail
: > "$CURL_ARGS_FILE"
: > "$CURL_PAYLOAD_FILE"
config_path=""
while (($#)); do
  case "$1" in
    --config)
      config_path="$2"
      shift 2
      ;;
    *)
      printf '%s\n' "$1" >> "$CURL_ARGS_FILE"
      shift
      ;;
  esac
done
cat "$config_path" > "$CURL_CONFIG_FILE"
cat > "$CURL_PAYLOAD_FILE"
if [[ "${CURL_FAIL:-0}" == 1 ]]; then
  echo 'simulated delivery failure' >&2
  exit 22
fi
CURL_STUB
chmod +x "$tmpdir/bin/curl"
export PATH="$tmpdir/bin:$PATH"
export CURL_ARGS_FILE="$tmpdir/curl-args"
export CURL_CONFIG_FILE="$tmpdir/curl-config"
export CURL_PAYLOAD_FILE="$tmpdir/payload.json"

source "${NIGHTLY_SUMMARY_HELPER:-$repo_root/modules/services/scripts/nightly-summary.sh}"
source "${NIGHTLY_LOG_HELPER:-$repo_root/modules/services/scripts/nightly-log.sh}"
source "${NIGHTLY_GCROOTS_HELPER:-$repo_root/modules/services/scripts/nightly-gcroots.sh}"
source "${NIGHTLY_ACTIVATE_HELPER:-$repo_root/modules/services/scripts/nightly-activate.sh}"
source "${NIGHTLY_NOTIFY_HELPER:-$repo_root/modules/services/scripts/nightly-notify.sh}"
source "${NIGHTLY_FINISH_HELPER:-$repo_root/modules/services/scripts/nightly-finish.sh}"
source "${NIGHTLY_SIGNALS_HELPER:-$repo_root/modules/services/scripts/nightly-signals.sh}"

# The updater must not promote or activate a snapshot after main advances.
stale_bare="$tmpdir/stale-main.git"
stale_writer="$tmpdir/stale-writer"
stale_job="$tmpdir/stale-job"
git -c init.defaultBranch=main init --bare "$stale_bare" >/dev/null
git clone "$stale_bare" "$stale_writer" >/dev/null 2>&1
git -C "$stale_writer" checkout -b main >/dev/null 2>&1
git -C "$stale_writer" config user.name test
git -C "$stale_writer" config user.email test@example.invalid
printf 'initial\n' > "$stale_writer/source"
git -C "$stale_writer" add source
git -C "$stale_writer" commit -m initial >/dev/null
git -C "$stale_writer" push -u origin main >/dev/null 2>&1
git clone --branch main "$stale_bare" "$stale_job" >/dev/null 2>&1
repo_git() { git "$@"; }
(
  cd "$stale_job"
  branch=main
  activation_deferred=0
  summary=""
  verify_main_revision
  [[ "$activation_deferred" -eq 0 ]]
)
printf 'advanced\n' >> "$stale_writer/source"
git -C "$stale_writer" add source
git -C "$stale_writer" commit -m advance >/dev/null
git -C "$stale_writer" push >/dev/null 2>&1
(
  cd "$stale_job"
  branch=main
  activation_deferred=0
  summary=""
  verify_main_revision
  [[ "$activation_deferred" -eq 1 ]]
  grep -Fq 'main advanced during the run' <<< "$summary"
)

# A failed push must leave staged outputs unpromoted and must not run nix-env.
mkdir -p "$tmpdir/gcroots" "$tmpdir/staging"
printf '#!%s\nprintf called > %q\n' "$BASH" "$tmpdir/nix-env-called" > "$tmpdir/nix-env"
chmod +x "$tmpdir/nix-env"
ln -s /nix/store/test-unpublished "$tmpdir/staging/host-test"
gcroots_dir="$tmpdir/gcroots"
tmp_gcroots="$tmpdir/staging"
activation_deferred=1
host_label=test
nix_env_bin="$tmpdir/nix-env"
summary=""
complete_nightly_run
[[ ! -L "$gcroots_dir/host-test" ]]
[[ -L "$tmp_gcroots/host-test" ]]
[[ ! -e "$tmpdir/nix-env-called" ]]
grep -Fq 'activation was deferred' <<< "$summary"
(
  notify_enabled=0
  activation_deferred=1
  tmp_gcroots="$tmpdir/staging"
  log_redirected=0
  build_pid=""
  signal_received=0
  stage="cleanup"
  log_file="$tmpdir/last-run.log"
  summary=""
  trap finish_nightly_run EXIT
  exit 0
)
[[ ! -e "$tmpdir/staging" ]]

# The EXIT handler preserves an existing failure even if Discord delivery fails.
notify_enabled=1
webhook_file="$tmpdir/webhook"
printf 'https://discord.example/api/webhooks/test-secret\n' > "$webhook_file"
host_label=test
log_file="$tmpdir/last-run.log"
activation_deferred=0
tmp_gcroots=""
log_redirected=0
build_pid=""
signal_received=0
stage="test failure"
summary=""

# A late main advance may leave published cache roots ahead of the running
# generation. Keep the second freshness check and make that policy explicit.
(
  cd "$stale_job"
  git reset --hard origin/main >/dev/null
  branch=main
  work="$tmpdir/late-advance"
  gcroots_dir="$work/roots"
  tmp_gcroots="$gcroots_dir/.staging.current"
  mkdir -p "$tmp_gcroots" "$work/new-closure"
  ln -s "$work/new-closure" "$tmp_gcroots/host-test"
  hosts=(test)
  activation_deferred=0
  summary=""
  fetches=0
  repo_git() {
    if [[ "$1" == fetch ]]; then
      fetches=$((fetches + 1))
      if [[ "$fetches" -eq 2 ]]; then
        printf 'late change\n' >> "$stale_writer/source"
        git -C "$stale_writer" commit -am 'late advance' >/dev/null
        git -C "$stale_writer" push >/dev/null 2>&1
      fi
    fi
    git "$@"
  }
  complete_nightly_run
  [[ "$fetches" -eq 2 ]]
  [[ "$activation_deferred" -eq 1 ]]
  [[ -z "$tmp_gcroots" ]]
  [[ "$(readlink "$gcroots_dir/host-test")" == "$work/new-closure" ]]
  [[ ! -e "$tmpdir/nix-env-called" ]]
  grep -Fq 'tested closures remain cached' <<< "$summary"
)

# Real logger + EXIT reporter must identify failures after the final revision
# check as self-upgrade failures, preserving both the exit code and private log.
for failure in profile activation; do
  work="$tmpdir/failure-$failure"
  mkdir -p "$work/closure/bin"
  printf '#!%s\n' "$BASH" > "$work/nix-env"
  cat >> "$work/nix-env" <<'NIX_ENV_STUB'
[[ ! -e /proc/self/fd/5 && ! -e /proc/self/fd/6 ]] || exit 71
[[ "$(umask)" == 0022 ]] || exit 72
printf 'PRIVATE_PROFILE_OUTPUT\n'
exit "$NIX_ENV_STATUS"
NIX_ENV_STUB
  printf '#!%s\n' "$BASH" > "$work/closure/bin/switch-to-configuration"
  cat >> "$work/closure/bin/switch-to-configuration" <<'SWITCH_STUB'
[[ ! -e /proc/self/fd/5 && ! -e /proc/self/fd/6 ]] || exit 73
[[ "$(umask)" == 0022 ]] || exit 74
printf 'PRIVATE_ACTIVATION_OUTPUT\n'
exit 42
SWITCH_STUB
  chmod +x "$work/nix-env" "$work/closure/bin/switch-to-configuration"
  expected=42
  export NIX_ENV_STATUS=0
  if [[ "$failure" == profile ]]; then
    expected=37
    export NIX_ENV_STATUS=37
  fi
  set +e
  (
    set -e
    umask 0022
    cd "$stale_job"
    git reset --hard origin/main >/dev/null
    branch=main
    gcroots_dir="$work/roots"
    tmp_gcroots="$gcroots_dir/.staging.current"
    mkdir -p "$tmp_gcroots"
    ln -s "$work/closure" "$tmp_gcroots/host-test"
    hosts=(test)
    nix_env_bin="$work/nix-env"
    current_system_link="$work/not-current"
    state_dir="$work/state"
    log_file="$state_dir/last-run.log"
    stage=startup
    summary=""
    activation_deferred=0
    install_nightly_signal_traps
    start_private_log
    complete_nightly_run
  ) >"$work/journal" 2>&1
  actual=$?
  set -e
  [[ "$actual" -eq "$expected" ]]
  jq -e --arg status "$expected" '
    .embeds[0].description
    | contains("**Stage:** self-upgrade test") and contains("**Exit code:** " + $status)
  ' "$CURL_PAYLOAD_FILE" >/dev/null
  grep -Fq 'PRIVATE_PROFILE_OUTPUT' "$work/state/last-run.log"
  if [[ "$failure" == activation ]]; then
    grep -Fq 'PRIVATE_ACTIVATION_OUTPUT' "$work/state/last-run.log"
  fi
  if grep -Fq 'PRIVATE_' "$work/journal" "$CURL_PAYLOAD_FILE"; then
    echo 'private activation output escaped the log' >&2
    exit 1
  fi
done

# No nixpkgs update is a calm success only after the rest of the run succeeds.
(
  lock_updated=0
  install_nightly_signal_traps
  exit 0
)
jq -e '.embeds[0].title == "🌙 No nixpkgs updates · test" and .embeds[0].color == 5793266' "$CURL_PAYLOAD_FILE" >/dev/null
(
  lock_updated=1
  install_nightly_signal_traps
  exit 0
)
jq -e '.embeds[0].title == "✅ Nightly update complete · test"' "$CURL_PAYLOAD_FILE" >/dev/null
(
  lock_updated=0
  activation_deferred=1
  install_nightly_signal_traps
  exit 0
)
jq -e '.embeds[0].title == "⚠️ Nightly update deferred · test"' "$CURL_PAYLOAD_FILE" >/dev/null

# Even if no update was available, a failed pre-build is still a failure.
export CURL_FAIL=1
set +e
(
  lock_updated=0
  install_nightly_signal_traps
  exit 37
) 2>"$tmpdir/exit-error"
exit_status=$?
set -e
[[ "$exit_status" -eq 37 ]]
grep -Fq 'could not deliver Discord notification' "$tmpdir/exit-error"
jq -e '.embeds[0].title == "❌ Nightly run failed · test" and (.embeds[0].description | contains("**Exit code:** 37"))' "$CURL_PAYLOAD_FILE" >/dev/null

# TERM maps to timeout status 124, runs the same EXIT reporter, and remains
# best-effort when notification transport is unavailable.
(
  signal_received=0
  build_pid=""
  stage="pre-build"
  summary=""
  install_nightly_signal_traps
  state_dir="$tmpdir/timeout-state"
  log_file="$state_dir/last-run.log"
  start_private_log
  : > "$tmpdir/timeout-ready"
  sleep 30 5>&- 6>&- &
  build_pid=$!
  wait "$build_pid"
) >/dev/null 2>"$tmpdir/timeout-error" &
worker_pid=$!
for _ in {1..100}; do
  [[ -e "$tmpdir/timeout-ready" ]] && break
  sleep 0.01
done
[[ -e "$tmpdir/timeout-ready" ]]
kill -TERM "$worker_pid"
set +e
wait "$worker_pid"
timeout_status=$?
set -e
[[ "$timeout_status" -eq 124 ]]
grep -Fq 'could not deliver Discord notification' "$tmpdir/timeout-error"
jq -e '
  .embeds[0].description
  | contains("**Stage:** pre-build") and contains("**Exit code:** 124")
' "$CURL_PAYLOAD_FILE" >/dev/null

echo 'nightly flow tests passed'
