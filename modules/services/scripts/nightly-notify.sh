# Shared with tests/nightly-notify.sh.
notify_discord() {
  local status="$1" body="$2" url url_config title color payload curl_status
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
      title="✅ Nightly update complete · $host_label"
      color=3066993
      ;;
    up_to_date)
      title="🌙 No nixpkgs updates · $host_label"
      color=5793266
      ;;
    warning)
      title="⚠️ Nightly update deferred · $host_label"
      color=16761095
      ;;
    *)
      title="❌ Nightly run failed · $host_label"
      color=15158332
      ;;
  esac

  # jq slices Unicode code points; the 2000-code-point cap also stays
  # below Discord's 4096 UTF-16-unit description limit for emoji-heavy text.
  if ! payload="$(printf '%s\0%s\0%s' "$title" "$color" "$body" | jq -Rs \
    'split("\u0000") as [$title, $color, $body]
     | {
       username: "Nix Nightly",
       avatar_url: "https://raw.githubusercontent.com/Irgendeinwer/NixOS-Dotfiles/main/assets/nightly-icon.png",
       allowed_mentions: {parse: []},
       embeds: [{
         title: $title,
         description: (if ($body | length) <= 2000 then $body
                       else "…(truncated)\n" + ($body[-1900:])
                       end),
         color: ($color | tonumber),
         footer: {text: "NixOS · Nightly build"}
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
  if printf '%s' "$payload" | curl \
    --config <(printf 'url = "%s"\n' "$url_config") \
    --globoff --proto '=https' --silent --fail-with-body --max-time 8 \
    --retry 2 --retry-delay 2 --retry-connrefused --retry-max-time 15 \
    --header 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1; then
    return 0
  else
    curl_status=$?
    # Parser errors and HTTP bodies can echo credentials, even with globbing
    # disabled. Only report a numeric status after restoring the journal FDs.
    echo "nix-nightly-update: warning: could not deliver Discord notification (curl exit $curl_status)." >&2
  fi
}
