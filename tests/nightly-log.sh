#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${NIGHTLY_LOG_HELPER:-$repo_root/modules/services/scripts/nightly-log.sh}"
source "${NIGHTLY_SUMMARY_HELPER:-$repo_root/modules/services/scripts/nightly-summary.sh}"
source "${NIGHTLY_FINISH_HELPER:-$repo_root/modules/services/scripts/nightly-finish.sh}"
source "${NIGHTLY_SIGNALS_HELPER:-$repo_root/modules/services/scripts/nightly-signals.sh}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

state_dir="$tmpdir/state"
log_file="$state_dir/last-run.log"
mkdir -p "$state_dir"
chmod 0755 "$state_dir"
printf 'stale previous run\n' > "$log_file"
chmod 0644 "$log_file"

umask 0022
prepare_private_log
[[ "$(stat -c '%a' "$state_dir")" == 700 ]]
[[ "$(stat -c '%a' "$log_file")" == 600 ]]
[[ ! -s "$log_file" ]]
[[ "$(umask)" == 0022 ]]
: > "$tmpdir/boot-artifact"
mkdir "$tmpdir/boot-directory"
[[ "$(stat -c '%a' "$tmpdir/boot-artifact")" == 644 ]]
[[ "$(stat -c '%a' "$tmpdir/boot-directory")" == 755 ]]
umask 0027
prepare_private_log
[[ "$(umask)" == 0027 ]]

# Exercise real startup, child output, EXIT handling, and FD cleanup together.
# There must be no asynchronous logger/watchdog left to drain or signal.
notify_discord() {
  if [[ -e /proc/self/fd/5 || -e /proc/self/fd/6 ]]; then
    echo 'saved log descriptors leaked' >&2
    return 1
  fi
  printf 'report: %s; saved descriptors closed\n' "$1"
  printf 'report diagnostic\n' >&2
}
for status in 0 23; do
  set +e
  (
    set -e
    state_dir="$tmpdir/run-$status"
    log_file="$state_dir/last-run.log"
    stage="test stage"
    summary=""
    activation_deferred=0
    log_redirected=0
    lock_updated=1
    install_nightly_signal_traps
    start_private_log
    printf 'PRIVATE_STDOUT\n'
    printf 'PRIVATE_STDERR\n' >&2
    GIT_SSH_COMMAND=test-ssh NIX_SSHOPTS=test-options run_private "$BASH" -c '
      [[ "$GIT_SSH_COMMAND" == test-ssh && "$NIX_SSHOPTS" == test-options ]] || exit 70
      [[ ! -e /proc/self/fd/5 && ! -e /proc/self/fd/6 ]] || exit 71
      printf "PRIVATE_CHILD_STDOUT\n"
      printf "PRIVATE_CHILD_STDERR\n" >&2
    '

    [[ -z "$(jobs -pr)" ]]
    exit "$status"
  ) >"$tmpdir/journal-out" 2>"$tmpdir/journal-err"
  actual_status=$?
  set -e
  [[ "$actual_status" -eq "$status" ]]
  expected=success
  [[ "$status" -eq 0 ]] || expected=failure
  grep -Fxq "report: $expected; saved descriptors closed" "$tmpdir/journal-out"
  grep -Fxq 'report diagnostic' "$tmpdir/journal-err"
  if grep -Fq 'PRIVATE_' "$tmpdir/journal-out" "$tmpdir/journal-err"; then
    echo 'private command output leaked to the journal' >&2
    exit 1
  fi
  for marker in PRIVATE_STDOUT PRIVATE_STDERR PRIVATE_CHILD_STDOUT PRIVATE_CHILD_STDERR; do
    grep -Fxq "$marker" "$tmpdir/run-$status/last-run.log"
  done
  [[ "$(stat -c '%a' "$tmpdir/run-$status/last-run.log")" == 600 ]]
done

# A pre-redirection failure still reports cleanly without restoring unopened FDs.
: > "$tmpdir/blocked-state"
set +e
(
  set -e
  state_dir="$tmpdir/blocked-state"
  log_file="$state_dir/last-run.log"
  stage=startup
  summary=""
  activation_deferred=0
  log_redirected=0
  install_nightly_signal_traps
  start_private_log
) >"$tmpdir/startup-out" 2>"$tmpdir/startup-err"
startup_status=$?
set -e
[[ "$startup_status" -ne 0 ]]
grep -Fxq 'report: failure; saved descriptors closed' "$tmpdir/startup-out"
if grep -Fq 'Bad file descriptor' "$tmpdir/startup-err"; then
  echo 'attempted to restore unopened log descriptors' >&2
  exit 1
fi

# Also cover an open failure after the original descriptors have been saved.
set +e
(
  set -e
  prepare_private_log() { :; }
  log_file="$tmpdir/nonexistent/last-run.log"
  stage=startup
  summary=""
  activation_deferred=0
  log_redirected=0
  install_nightly_signal_traps
  start_private_log
) >"$tmpdir/open-out" 2>"$tmpdir/open-err"
open_status=$?
set -e
[[ "$open_status" -ne 0 ]]
grep -Fxq 'report: failure; saved descriptors closed' "$tmpdir/open-out"

[[ "$(format_duration 0)" == '0s' ]]
[[ "$(format_duration 59)" == '59s' ]]
[[ "$(format_duration 60)" == '1m 0s' ]]
[[ "$(format_duration 3599)" == '59m 59s' ]]
[[ "$(format_duration 3600)" == '1h 0m 0s' ]]
[[ "$(format_duration 3661)" == '1h 1m 1s' ]]
echo 'nightly log lifecycle tests passed'
