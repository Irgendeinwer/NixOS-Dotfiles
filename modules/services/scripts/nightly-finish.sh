finish_nightly_run() {
  local status=$?
  trap - EXIT
  # systemd also signals the service cgroup. This best-effort kill only
  # applies to a still-recorded build client, never a stale completed PID.
  if [ "${signal_received:-0}" -eq 1 ] && [ -n "${build_pid:-}" ]; then
    kill "$build_pid" 2>/dev/null || true
  fi
  if [ -n "${tmp_gcroots:-}" ] && [ -d "$tmp_gcroots" ]; then
    rm -rf "$tmp_gcroots" || true
  fi
  if [ -n "${tee_pid:-}" ]; then
    # Restore the journal streams and give tee a brief chance to flush.
    # During systemd cgroup shutdown, this remains best-effort.
    exec 1>&5 2>&6
    ( sleep 3; kill "$tee_pid" 2>/dev/null || true ) >/dev/null 2>&1 &
    wait "$tee_pid" 2>/dev/null || true
  fi
  add_summary "duration: $(format_duration "$SECONDS")"
  if [ "$status" -eq 0 ]; then
    if [ "$activation_deferred" -eq 1 ]; then
      notify_discord warning "$summary" || true
    else
      notify_discord success "$summary" || true
    fi
  else
    notify_discord failure "$(
      printf 'stage: %s\nexit code: %s\n\n%s\nFull log retained locally at %s' \
        "$stage" "$status" "$summary" "$log_file"
    )" || true
  fi
  exit "$status"
}
