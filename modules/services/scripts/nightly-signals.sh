install_nightly_signal_traps() {
  trap finish_nightly_run EXIT
  # systemd normally sends SIGTERM for TimeoutStartSec; keep a distinct
  # internal status so the final notification can report a timeout accurately.
  trap 'signal_received=1; exit 124' TERM
  trap 'signal_received=1; exit 130' INT
}
