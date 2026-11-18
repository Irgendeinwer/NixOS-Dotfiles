#!/usr/bin/env bash
set -euo pipefail

guard=${ZEN_PROFILE_GUARD:?set ZEN_PROFILE_GUARD to check-zen-profile.sh}
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
config_dir="$tmp/Zen data/.zen"
profile="$config_dir/existing.default"
store="$tmp/nix store"
mkdir -p "$config_dir" "$store"

expect_failure() {
  if bash "$guard" "$@" >"$tmp/message" 2>&1; then
    echo "Expected the Zen adoption guard to fail: $*" >&2
    exit 1
  fi
}

# Never make a missing registry or profile directory as an accidental new profile.
expect_failure "$config_dir" "$profile" "$store" yes
grep -q 'profiles.ini is missing' "$tmp/message"
printf '[Profile0]\nPath=existing.default\n' >"$config_dir/profiles.ini"
expect_failure "$config_dir" "$profile" "$store" yes
grep -q 'refusing to create a new profile' "$tmp/message"
mkdir -p "$profile"
bash "$guard" "$config_dir" "$profile" "$store" yes

# Existing regular files and foreign (including dangling) symlinks are left
# alone; the user must migrate preferences before Home Manager can adopt them.
printf 'user_pref("important.pref", true);\n' >"$profile/user.js"
expect_failure "$config_dir" "$profile" "$store" yes
grep -q 'not managed by Home Manager' "$tmp/message"
grep -q 'important.pref' "$profile/user.js"
bash "$guard" "$config_dir" "$profile" "$store" no
rm -- "$profile/user.js"
ln -s "$tmp/foreign-user.js" "$profile/user.js"
expect_failure "$config_dir" "$profile" "$store" yes
[ -L "$profile/user.js" ]
printf 'foreign\n' >"$tmp/foreign-user.js"
expect_failure "$config_dir" "$profile" "$store" yes
[ "$(cat "$tmp/foreign-user.js")" = foreign ]
rm -- "$profile/user.js"

# A symlink from any Home Manager generation may be updated normally.
managed="$store/hash-home-manager-files/.zen/existing.default"
mkdir -p "$managed"
printf 'managed\n' >"$managed/user.js"
ln -s "$managed/user.js" "$profile/user.js"
bash "$guard" "$config_dir" "$profile" "$store" yes
[ -L "$profile/user.js" ]
expect_failure "$config_dir" "$profile" "$store" invalid

echo 'Zen profile adoption guard: PASS'
