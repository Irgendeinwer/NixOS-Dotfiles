#!/usr/bin/env bash
# Refuse to create a missing profile or silently replace an existing user.js
# when adopting a browser-owned profile into Home Manager.
set -eu

if [ "$#" -ne 4 ]; then
  echo "Usage: check-zen-profile CONFIG_DIR PROFILE_DIR STORE_DIR MANAGE_USER_JS" >&2
  exit 2
fi

config_dir=$1
profile_dir=$2
store_dir=$3
manage_user_js=$4
case "$manage_user_js" in
  yes|no) ;;
  *) echo "MANAGE_USER_JS must be yes or no" >&2; exit 2 ;;
esac

if [ ! -f "$config_dir/profiles.ini" ]; then
  echo "Zen profile adoption: $config_dir/profiles.ini is missing; refusing to create a new profile." >&2
  echo "Verify the existing profile and see docs/zen-browser.md before activating." >&2
  exit 1
fi

if [ ! -d "$profile_dir" ]; then
  echo "Zen profile adoption: $profile_dir is missing; refusing to create a new profile." >&2
  echo "Verify the existing profile and see docs/zen-browser.md before activating." >&2
  exit 1
fi

if [ "$manage_user_js" = yes ]; then
  target="$profile_dir/user.js"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -L "$target" ]; then
      link=$(readlink -- "$target")
      case "$link" in
        "$store_dir"/*-home-manager-files/*) exit 0 ;;
      esac
    fi

    echo "Zen profile adoption: $target is not managed by Home Manager." >&2
    echo "Back it up, migrate any preferences, and move it aside before activating." >&2
    echo "See docs/zen-browser.md; no existing user.js was changed." >&2
    exit 1
  fi
fi
