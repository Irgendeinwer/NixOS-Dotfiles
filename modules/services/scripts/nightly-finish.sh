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
  restore_private_log
  add_summary "duration: $(format_duration "$SECONDS")"
  if [ "$status" -eq 0 ]; then
    if [ "$activation_deferred" -eq 1 ]; then
      notify_discord warning "$summary" || true
    elif [ "${lock_updated:-0}" -eq 0 ]; then
      notify_discord up_to_date "$summary" || true
    else
      notify_discord success "$summary" || true
    fi
  else
    notify_discord failure "$(
      printf "**Stage:** %s\n**Exit code:** %s\n\n%s\nFull log: \`%s\`" \
        "$stage" "$status" "$summary" "$log_file"
    )" || true
  fi
  exit "$status"
}
