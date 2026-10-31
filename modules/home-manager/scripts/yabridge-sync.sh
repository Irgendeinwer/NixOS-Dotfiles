#!/usr/bin/env bash

# Bootstrap standard Windows VST2/VST3/CLAP folders inside the active Wine
# prefix, register them with yabridgectl, and sync bridged Linux bundles.

export WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"

if [[ ! -d "$WINEPREFIX/drive_c" ]]; then
  printf 'Initializing Wine prefix at %s...\n' "$WINEPREFIX"
  WINEDLLOVERRIDES="mscoree,mshtml=" wineboot --init
  wineserver --wait
fi

default_dirs=(
  "$WINEPREFIX/drive_c/Program Files/Common Files/VST3"
  "$WINEPREFIX/drive_c/Program Files/Common Files/CLAP"
  "$WINEPREFIX/drive_c/Program Files/Steinberg/VstPlugins"
  "$WINEPREFIX/drive_c/Program Files/VstPlugins"
)

for dir in "${default_dirs[@]}"; do
  mkdir -p "$dir"
  yabridgectl add "$dir"
done

for extra_dir in "$@"; do
  if [[ -d "$extra_dir" ]]; then
    yabridgectl add "$extra_dir"
  else
    printf 'Skipping non-existent directory: %s\n' "$extra_dir" >&2
  fi
done

yabridgectl sync --prune
yabridgectl status
