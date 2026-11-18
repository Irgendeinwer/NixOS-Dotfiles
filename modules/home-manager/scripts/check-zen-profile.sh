#!/usr/bin/env bash
# Refuse to create a missing profile or silently replace existing profile
# files when adopting a browser-owned profile into Home Manager.
set -eu

if [ "$#" -lt 4 ]; then
  echo "Usage: check-zen-profile CONFIG_DIR PROFILE_DIR STORE_DIR MANAGE_USER_JS [OTHER_TARGET ...]" >&2
  exit 2
fi

config_dir=$1
profile_dir=$2
store_dir=$3
manage_user_js=$4
shift 4
case "$manage_user_js" in
  yes|no) ;;
  *) echo "MANAGE_USER_JS must be yes or no" >&2; exit 2 ;;
esac

# A link into an old Home Manager generation can disappear during orphan
# cleanup because the new generation deliberately does not own profiles.ini.
if [ -L "$config_dir/profiles.ini" ]; then
  echo "Zen profile adoption: $config_dir/profiles.ini is a symlink; a browser-owned regular file is required." >&2
  echo "Back up the link and its contents, then preserve the registry as a regular file. See docs/zen-browser.md." >&2
  exit 1
fi

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

check_target() {
  target=$1
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -L "$target" ]; then
      link=$(readlink -- "$target")
      case "$link" in
        "$store_dir"/*-home-manager-files/*) return 0 ;;
      esac
    fi

    echo "Zen profile adoption: $target is not managed by Home Manager." >&2
    echo "Back it up, migrate any wanted settings or CSS, and move it aside before activating." >&2
    echo "See docs/zen-browser.md; the existing file was not changed." >&2
    exit 1
  fi
}

if [ "$manage_user_js" = yes ]; then
  check_target "$profile_dir/user.js"
fi
for target in "$@"; do
  check_target "$target"
done
