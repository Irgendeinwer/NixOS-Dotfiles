write_nightly_status() {
  local run_state="$1" exit_code="$2" duration_sec="$3" duration_human="$4"
  local status_dir tmp_status finished_at hosts_json
  if [ -z "${status_file:-}" ]; then
    return 0
  fi
  status_dir="$(dirname "$status_file")"
  mkdir -p "$status_dir" || return 0
  tmp_status="$(mktemp "$status_dir/.status.XXXXXX")" || return 0
  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ "${hosts+set}" = set ] && [ "${#hosts[@]}" -gt 0 ]; then
    hosts_json="$(printf '%s\n' "${hosts[@]}" | jq -R . | jq -s .)"
  else
    hosts_json="[]"
  fi
  if jq -n \
    --arg host "${host_label:-unknown}" \
    --arg state "$run_state" \
    --arg stage "${stage:-unknown}" \
    --arg finished_at "$finished_at" \
    --arg duration_human "$duration_human" \
    --arg summary "$summary" \
    --argjson exit_code "$exit_code" \
    --argjson duration_sec "$duration_sec" \
    --argjson lock_updated "${lock_updated:-0}" \
    --argjson activation_deferred "${activation_deferred:-0}" \
    --argjson hosts "$hosts_json" \
    '{
      schemaVersion: 1,
      host: $host,
      state: $state,
      stage: $stage,
      exitCode: $exit_code,
      lockUpdated: ($lock_updated == 1),
      activationDeferred: ($activation_deferred == 1),
      finishedAt: $finished_at,
      durationSeconds: $duration_sec,
      durationHuman: $duration_human,
      hosts: $hosts,
      summary: ($summary | split("\n") | map(select(length > 0)))
    }' > "$tmp_status"; then
    chmod 0644 "$tmp_status" && mv -f "$tmp_status" "$status_file"
  else
    rm -f "$tmp_status"
  fi
}

finish_nightly_run() {
  local status=$?
  local duration_sec="$SECONDS"
  local duration_human run_state
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
  duration_human="$(format_duration "$duration_sec")"
  add_summary "duration: $duration_human"
  if [ "$status" -eq 0 ]; then
    if [ "${activation_deferred:-0}" -eq 1 ]; then
      run_state="warning"
      notify_discord warning "$summary" || true
    elif [ "${lock_updated:-0}" -eq 0 ]; then
      run_state="up_to_date"
      notify_discord up_to_date "$summary" || true
    else
      run_state="success"
      notify_discord success "$summary" || true
    fi
  else
    run_state="failure"
    notify_discord failure "$(
      printf "**Stage:** %s\n**Exit code:** %s\n\n%s\nFull log: \`%s\`" \
        "$stage" "$status" "$summary" "$log_file"
    )" || true
  fi
  write_nightly_status "$run_state" "$status" "$duration_sec" "$duration_human" || true
  exit "$status"
}
