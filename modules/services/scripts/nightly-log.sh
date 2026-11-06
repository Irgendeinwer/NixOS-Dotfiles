prepare_private_log() {
  mkdir -p "$state_dir"
  chmod 0700 "$state_dir"
  umask 077
  : > "$log_file"
  chmod 0600 "$log_file"
}
