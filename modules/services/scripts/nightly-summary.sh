add_summary() {
  summary="$summary• $1"$'\n'
}

format_duration() {
  local total="$1" hours minutes seconds
  hours=$((total / 3600))
  minutes=$(((total % 3600) / 60))
  seconds=$((total % 60))
  if [ "$hours" -gt 0 ]; then
    printf '%dh %dm %ds' "$hours" "$minutes" "$seconds"
  elif [ "$minutes" -gt 0 ]; then
    printf '%dm %ds' "$minutes" "$seconds"
  else
    printf '%ds' "$seconds"
  fi
}
