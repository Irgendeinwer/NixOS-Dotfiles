# Shared with tests/nightly-notify.sh.
notify_discord() {
  local status="$1" body="$2" url url_config title color payload response
  if [ "$notify_enabled" != "1" ]; then
    return 0
  fi
  if [ ! -s "$webhook_file" ]; then
    echo "nix-nightly-update: no webhook URL in $webhook_file (add nix_nightly_webhook to the host sops file); skipping notification." >&2
    return 0
  fi
  url="$(tr -d '[:space:]' < "$webhook_file")"
  if [ -z "$url" ]; then
    echo "nix-nightly-update: webhook URL in $webhook_file is empty; skipping notification." >&2
    return 0
  fi
  case "$status" in
    success)
      title=":white_check_mark: Nightly update succeeded on $host_label"
      color=3066993
      ;;
    warning)
      title=":warning: Nightly update finished with warnings on $host_label"
      color=16761095
      ;;
    *)
      title=":x: Nightly update FAILED on $host_label"
      color=15158332
      ;;
  esac

  # jq slices Unicode code points; the 2000-code-point cap also stays
  # below Discord's 4096 UTF-16-unit description limit for emoji-heavy text.
  if ! payload="$(printf '%s\0%s\0%s' "$title" "$color" "$body" | jq -Rs \
    'split("\u0000") as [$title, $color, $body]
     | {
       username: "nix-nightly",
       embeds: [{
         title: $title,
         description: (if ($body | length) <= 2000 then $body
                       else "…(truncated)\n" + ($body[-1900:])
                       end),
         color: ($color | tonumber)
       }]
     }')"; then
    echo "nix-nightly-update: warning: could not encode Discord notification; skipping." >&2
    return 0
  fi

  # Keep both the webhook and JSON body out of curl's argv: supply URL via
  # a process-substitution config fd and stream the payload on stdin. Escape
  # curl-config quoted-string characters before writing the private config.
  url_config="${url//\\/\\\\}"
  url_config="${url_config//\"/\\\"}"
  if ! response="$(printf '%s' "$payload" | curl \
    --config <(printf 'url = "%s"\n' "$url_config") \
    --silent --show-error --fail-with-body --max-time 8 \
    --retry 2 --retry-delay 2 --retry-connrefused --retry-max-time 15 \
    --header 'Content-Type: application/json' --data-binary @- 2>&1)"; then
    echo "nix-nightly-update: warning: could not deliver Discord notification: $response" >&2
  fi
}
