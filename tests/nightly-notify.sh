#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin"
printf '#!%s\n' "$BASH" > "$tmpdir/bin/curl"
cat >> "$tmpdir/bin/curl" <<'CURL_STUB'
set -euo pipefail
: > "$CURL_ARGS_FILE"
: > "$CURL_PAYLOAD_FILE"
config_path=""
while (($#)); do
  case "$1" in
    --config)
      config_path="$2"
      printf '%s\n%s\n' "$1" "$2" >> "$CURL_ARGS_FILE"
      shift 2
      ;;
    *)
      printf '%s\n' "$1" >> "$CURL_ARGS_FILE"
      shift
      ;;
  esac
done
cat "$config_path" > "$CURL_CONFIG_FILE"
cat > "$CURL_PAYLOAD_FILE"
if [[ "${CURL_FAIL:-0}" == 1 ]]; then
  printf 'simulated delivery failure\n' >&2
  exit 22
fi
CURL_STUB
chmod +x "$tmpdir/bin/curl"
real_jq="$(command -v jq)"
printf '#!%s\n' "$BASH" > "$tmpdir/bin/jq"
cat >> "$tmpdir/bin/jq" <<'JQ_STUB'
printf '%s\n' "$@" >> "$JQ_ARGS_FILE"
exec "$REAL_JQ" "$@"
JQ_STUB
chmod +x "$tmpdir/bin/jq"

export PATH="$tmpdir/bin:$PATH"
export REAL_JQ="$real_jq"
export JQ_ARGS_FILE="$tmpdir/jq-args"
: > "$JQ_ARGS_FILE"
export CURL_ARGS_FILE="$tmpdir/curl-args"
export CURL_CONFIG_FILE="$tmpdir/curl-config"
export CURL_PAYLOAD_FILE="$tmpdir/payload.json"

source "${NIGHTLY_NOTIFY_HELPER:-$repo_root/modules/services/scripts/nightly-notify.sh}"
notify_enabled=1
webhook_file="$tmpdir/webhook"
host_label="test-host"
token="test-token-not-for-argv"
printf 'https://discord.example/api/webhooks/%s\n' "$token" > "$webhook_file"

# Disabled notifications and a missing credential must not call curl.
notify_enabled=0
notify_discord success 'disabled' 2>/dev/null
[[ ! -e "$CURL_ARGS_FILE" ]]
notify_enabled=1
webhook_file="$tmpdir/missing-webhook"
notify_discord failure 'missing secret' 2>/dev/null
[[ ! -e "$CURL_ARGS_FILE" ]]
webhook_file="$tmpdir/webhook"

# A normal report carries JSON and reads the credential from curl config, not argv.
notify_discord warning 'flake.lock push deferred'
grep -Fq "https://discord.example/api/webhooks/$token" "$CURL_CONFIG_FILE"
if grep -Fq 'flake.lock push deferred' "$JQ_ARGS_FILE" \
  || grep -Fq 'test-host' "$JQ_ARGS_FILE"; then
  echo 'notification metadata leaked into jq arguments' >&2
  exit 1
fi
if grep -Fq "$token" "$CURL_ARGS_FILE" \
  || grep -Fq 'flake.lock push deferred' "$CURL_ARGS_FILE"; then
  echo 'webhook or payload content leaked into curl arguments' >&2
  exit 1
fi
jq -e '
  .username == "Nix Nightly"
  and .avatar_url == "https://raw.githubusercontent.com/Irgendeinwer/NixOS-Dotfiles/main/assets/nightly-icon.png"
  and .allowed_mentions.parse == []
  and .embeds[0].title == "⚠️ Nightly update deferred · test-host"
  and .embeds[0].footer.text == "NixOS · Nightly build"
  and .embeds[0].description == "flake.lock push deferred"
' "$CURL_PAYLOAD_FILE" >/dev/null

# Truncation is Unicode-safe and remains within Discord's UTF-16-unit limit.
long_body="$(jq -nr '"😀" * 3000')"
notify_discord failure "$long_body"
jq -e '
  (.embeds[0].description | startswith("…(truncated)\n"))
  and (.embeds[0].description | explode | map(if . > 65535 then 2 else 1 end) | add <= 4096)
' "$CURL_PAYLOAD_FILE" >/dev/null

# A transport failure is logged but does not fail the nightly run.
export CURL_FAIL=1
notify_discord success 'transport failure is non-fatal' 2>"$tmpdir/delivery-error"
grep -Fq 'could not deliver Discord notification' "$tmpdir/delivery-error"
if grep -Fq "$token" "$tmpdir/delivery-error"; then
  echo 'webhook token leaked into delivery diagnostics' >&2
  exit 1
fi

echo 'nightly notification tests passed'
