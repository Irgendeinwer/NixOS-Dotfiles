prepare_private_log() {
  # Explicit modes keep the log private without changing the caller's umask
  # (which is also inherited by nix-env and the boot-loader installer).
  install -d -m 0700 "$state_dir"
  install -m 0600 /dev/null "$log_file"
}

start_private_log() {
  prepare_private_log
  exec 5>&1 6>&2
  log_redirected=1
  # No pipe, tee process, flush watchdog, or delayed kill of a reusable PID.
  exec >>"$log_file" 2>&1
}

restore_private_log() {
  if [ "${log_redirected:-0}" -eq 1 ]; then
    exec 1>&5 2>&6
    exec 5>&- 6>&-
    log_redirected=0
  fi
}

run_private() {
  # Build clients, Git hooks and activation programs must not inherit the
  # saved journal descriptors. Keep them only in the controlling shell.
  "$@" 5>&- 6>&-
}
