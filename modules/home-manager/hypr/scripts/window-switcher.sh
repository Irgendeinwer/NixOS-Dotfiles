# Window switcher (ALT+TAB). Rofi's own window mode looks icons up by
# lowercased app_id in the icon theme only, with no desktop-file
# fallback, so apps whose desktop entry names a different icon
# (Signal, Zen, ...) show up iconless there. This feeds dmenu mode
# with the icon from each window's desktop entry instead, which is
# the same source drun uses, so the two always agree.
# Wrapped by writeShellApplication (errexit, nounset, pipefail, shellcheck).

icon_for() {
  # Echo the Icon= value of the desktop file for app_id $1. Falls back
  # to the lowercased app_id, which the icon theme may still know
  # under that name even without a matching desktop file.
  local class="$1" lower dir name file icon=""
  lower=$(printf '%s' "$class" | tr '[:upper:]' '[:lower:]')

  local -a data_dirs=()
  IFS=: read -r -a data_dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  local -a bases=("${XDG_DATA_HOME:-$HOME/.local/share}" "${data_dirs[@]}")

  # Desktop file named after the app_id, like drun expects.
  for dir in "${bases[@]}"; do
    for name in "$class" "$lower"; do
      file="$dir/applications/$name.desktop"
      if [ -f "$file" ]; then
        icon=$(sed -n 's/^Icon=//p' "$file" | head -n 1)
        break 2
      fi
    done
  done

  # No such file: match on StartupWMClass instead.
  if [ -z "$icon" ]; then
    for dir in "${bases[@]}"; do
      for file in "$dir"/applications/*.desktop; do
        [ -f "$file" ] || continue
        if grep -qxF "StartupWMClass=$class" "$file" ||
          grep -qxF "StartupWMClass=$lower" "$file"; then
          icon=$(sed -n 's/^Icon=//p' "$file" | head -n 1)
          break 2
        fi
      done
    done
  fi

  printf '%s' "${icon:-$lower}"
}

clients=$(hyprctl clients -j)

# Most recently focused first: focusHistoryID 0 is the active window,
# counting up by last focus; never-focused windows report -1, send
# those last.
mapfile -t rows < <(
  printf '%s' "$clients" | jq -r '
    sort_by(if .focusHistoryID < 0 then 1048576 else .focusHistoryID end)
    | .[]
    | [.address, .class, (.title | gsub("[\\t\\n\\r]"; " "))]
    | @tsv'
)

[ "${#rows[@]}" -gt 0 ] || exit 0

declare -a addrs=() texts=() icons=()
declare -A icon_cache=()
for row in "${rows[@]}"; do
  # Split by hand: read with a tab IFS would merge empty fields.
  addr=${row%%$'\t'*}
  rest=${row#*$'\t'}
  class=${rest%%$'\t'*}
  title=${rest#*$'\t'}
  addrs+=("$addr")
  if [ -n "$title" ]; then
    texts+=("$title")
  else
    texts+=("${class:-window}")
  fi
  if [ -z "$class" ]; then
    icons+=("")
  elif [[ -v icon_cache["$class"] ]]; then
    icons+=("${icon_cache["$class"]}")
  else
    icon=$(icon_for "$class")
    icon_cache["$class"]="$icon"
    icons+=("$icon")
  fi
done

rofi_args=(-dmenu -show-icons -format i -p "Windows")
# Preselect the previously used window, so Enter switches straight back.
if [ "${#rows[@]}" -gt 1 ]; then
  rofi_args+=(-selected-row 1)
fi

# The icon metadata is null-separated, which shell strings cannot
# hold, so entries are assembled while printing.
selected=$(
  for i in "${!addrs[@]}"; do
    printf '%s' "${texts[$i]}"
    if [ -n "${icons[$i]}" ]; then
      printf '\000icon\037%s' "${icons[$i]}"
    fi
    printf '\n'
  done | rofi "${rofi_args[@]}"
) || exit 0

[ -n "$selected" ] || exit 0
hyprctl dispatch "hl.dsp.focus({ window = 'address:${addrs[$selected]}' })"
