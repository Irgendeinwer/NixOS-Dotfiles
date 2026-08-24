#!/usr/bin/env bash

# Disable pipefail to prevent SIGPIPE (exit code 141) from fzf's early exits 
# from triggering errexit and crashing the script.
set +o pipefail

# Color Palette for visual feedback (ANSI Escape Sequences)
C_RESET=$'\e[0m'
C_GRAY=$'\e[0;90m'
C_PURPLE=$'\e[1;35m'
C_YELLOW=$'\e[1;33m'
C_GREEN=$'\e[1;32m'
C_CYAN=$'\e[1;36m'
C_WHITE=$'\e[0;37m'
C_GOLD=$'\e[0;33m'
C_MAGENTA=$'\e[0;35m'

# Ensure optional external variables do not fail under set -u (nounset)
LISTEN_MUSIC_DIR="${LISTEN_MUSIC_DIR:-}"
XDG_MUSIC_DIR=""

# Resolve Music Directory
MUSIC_DIR="${LISTEN_MUSIC_DIR:-}"

# 1. Try XDG user dir if not overridden
if [ -z "$MUSIC_DIR" ] && command -v xdg-user-dir &>/dev/null; then
  XDG_MUSIC_DIR=$(xdg-user-dir MUSIC)
  
  # Reject $HOME as a valid music directory fallback (prevents searching entire home)
  if [ -n "$XDG_MUSIC_DIR" ] && [ "$XDG_MUSIC_DIR" != "$HOME" ] && [ -d "$XDG_MUSIC_DIR" ]; then
    MUSIC_DIR="$XDG_MUSIC_DIR"
  fi
fi

# 2. Try standard directory fallbacks if XDG failed or pointed to $HOME
if [ -z "$MUSIC_DIR" ]; then
  if [ -d "$HOME/Music" ]; then
    MUSIC_DIR="$HOME/Music"
  elif [ -d "$HOME/music" ]; then
    MUSIC_DIR="$HOME/music"
  fi
fi

# Exit gracefully if no legitimate music directory is found
if [ -z "$MUSIC_DIR" ] || [ ! -d "$MUSIC_DIR" ]; then
  echo "Error: Could not resolve a valid music directory." >&2
  echo "Please create '$HOME/Music' or '$HOME/music', or set \$LISTEN_MUSIC_DIR." >&2
  exit 1
fi

playlist=()

show_help() {
  printf '\n%s🎵 listen%s %s—%s A minimalist terminal music player launcher powered by FZF and MPV.\n\n' "${C_PURPLE}" "${C_RESET}" "${C_GRAY}" "${C_RESET}"
  printf '%sUsage:%s\n' "${C_YELLOW}" "${C_RESET}"
  printf '  listen [options] [query]\n\n'
  printf '%sOptions:%s\n' "${C_YELLOW}" "${C_RESET}"
  printf '  %s-s%s             Shuffle playback\n' "${C_GREEN}" "${C_RESET}"
  printf '  %s-d%s             Directory mode (browse and play entire Artists/Albums)\n' "${C_GREEN}" "${C_RESET}"
  printf '  %s-g%s             GUI mode (opens an MPV window for cover art & visual playlist)\n' "${C_GREEN}" "${C_RESET}"
  printf '  %s-A%s             Artist mode (auto-appends all albums/tracks by the same artist)\n' "${C_GREEN}" "${C_RESET}"
  printf '  %s-o%s             One-shot mode (disables auto-append; plays only the selected track)\n' "${C_GREEN}" "${C_RESET}"
  printf '  %s-f%s             Fast-play mode (instantly plays the first match without opening the UI)\n' "${C_GREEN}" "${C_RESET}"
  printf '  %s-h, --help%s     Show this help screen\n\n' "${C_GREEN}" "${C_RESET}"
  printf '%sBehavior:%s\n' "${C_YELLOW}" "${C_RESET}"
  printf '  By default, selecting a single track will automatically queue the rest of\n'
  printf '  the album (all other tracks in the same directory). Use %s-A%s to expand this\n' "${C_GREEN}" "${C_RESET}"
  printf '  to the entire artist folder, or %s-o%s to play strictly your selection.\n\n' "${C_GREEN}" "${C_RESET}"
  printf '%sExamples:%s\n' "${C_YELLOW}" "${C_RESET}"
  printf '  listen                Browse and play tracks (queues the selected album)\n'
  printf '  listen daft punk      Search and play (instantly queues the matches)\n'
  printf '  listen -s             Browse and play tracks on shuffle\n'
  printf '  listen -d "discovery" Play matching folder contents ("Daft Punk/Discovery")\n'
  printf '  listen -g -s          Browse on shuffle with visual cover art/playlist preview window\n'
  printf '  listen -f daft punk   Instantly plays the top Daft Punk match and queues the album\n\n'
  printf '%sControls (during playback):%s\n' "${C_YELLOW}" "${C_RESET}"
  printf '  %s[Space]%s / Left Click  Play/Pause\n' "${C_CYAN}" "${C_RESET}"
  printf '  %s[Left] / [Right]%s      Seek back/forward 5s\n' "${C_CYAN}" "${C_RESET}"
  printf '  %s[Up] / [Down]%s         Volume up/down\n' "${C_CYAN}" "${C_RESET}"
  printf '  %s[p]%s (in GUI mode)     Open visual playlist queue (uosc)\n' "${C_CYAN}" "${C_RESET}"
  printf '  %s[q]%s                   Quit playback\n\n' "${C_CYAN}" "${C_RESET}"
}

# Normalize long option "--help" to "-h" prior to parsing
for arg in "$@"; do
  shift
  case "$arg" in
    --help) set -- "$@" "-h" ;;
    *)      set -- "$@" "$arg" ;;
  esac
done

shuffle=false
dir_mode=false
gui_mode=false
fast_mode=false
auto_mode="album" # Options: "album", "artist", "single"
auto_appended=false

# Parse options safely
while getopts "sdgoAhf" opt; do
  case "$opt" in
    s) shuffle=true ;;
    d) dir_mode=true ;;
    g) gui_mode=true ;;
    o) auto_mode="single" ;;
    A) auto_mode="artist" ;;
    f) fast_mode=true ;;
    h) show_help; exit 0 ;;
    *)
      echo "" >&2
      show_help >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))
query="$*"

# Enter music folder to keep FZF displays relatively pathed
cd "$MUSIC_DIR" || exit 1

if [ "$dir_mode" = "true" ]; then
  if [ "$fast_mode" = "true" ] && [ -n "$query" ]; then
    # Grab the top directory match non-interactively
    selected_dir=$(fd -L --type d --max-depth 2 --mindepth 1 . \
      | fzf --filter="$query" | head -n 1 || true)
  else
    # Browse directories interactively with symbolic link support (-L)
    selected_dir=$(fd -L --type d --max-depth 2 --mindepth 1 . \
      | fzf \
          --select-1 \
          --exit-0 \
          --query="$query" \
          --prompt="📁 Select Artist/Album > " \
          --layout=reverse \
          --height=50% \
          --border \
          --preview 'fd -L -e opus -e flac -e mp3 -e wav -e m4a --max-depth 2 . -- {} | sed "s|^.*/||"' \
          --preview-window=right:50%:wrap || true)
  fi

  if [ -z "$selected_dir" ]; then
    echo "No folder selected."
    exit 0
  fi

  # Resolve absolute paths from target directory
  selected_dir_abs="$MUSIC_DIR/$selected_dir"
  target_dir="$selected_dir_abs"

  # If Artist mode is enabled, target the parent of the chosen directory (Artist folder)
  if [ "$auto_mode" = "artist" ]; then
    artist_dir=$(dirname -- "$selected_dir_abs")
    # Verify the parent directory is valid and doesn't escape the root music directory
    if [ "$artist_dir" != "$MUSIC_DIR" ] && [[ "$artist_dir" == "$MUSIC_DIR"/* ]]; then
      target_dir="$artist_dir"
    fi
  fi

  # Resolve absolute paths from target directory
  selected_tracks=$(fd -L -e opus -e flac -e mp3 -e wav -e m4a -a . -- "$target_dir" || true)
  
  if [ -z "$selected_tracks" ]; then
    echo "Error: No music files found in '$target_dir'." >&2
    exit 1
  fi

  mapfile -t playlist <<< "$selected_tracks"
else
  if [ "$fast_mode" = "true" ] && [ -n "$query" ]; then
    # Grab the top track match non-interactively
    fzf_out=$(fd -L -e opus -e flac -e mp3 -e wav -e m4a . \
      | fzf --filter="$query" | head -n 1 || true)
  else
    # Browse individual tracks relative to the current directory
    fzf_out=$(fd -L -e opus -e flac -e mp3 -e wav -e m4a . \
      | fzf \
          --multi \
          --query="$query" \
          --select-1 \
          --exit-0 \
          --prompt="🎵 Select music > " \
          --header="[Tab] Multi-select | [Enter] Play" \
          --layout=reverse \
          --height=50% \
          --border \
          --preview 'dir=$(dirname -- {}); fd -L -e opus -e flac -e mp3 -e wav -e m4a --max-depth 1 . -- "$dir" | sed "s|^.*/||"' \
          --preview-window=right:50%:wrap || true)
  fi

  if [ -z "$fzf_out" ]; then
    echo "No music selected."
    exit 0
  fi

  mapfile -t selected_tracks <<< "$fzf_out"

  # Construct absolute playlist paths
  for track in "${selected_tracks[@]}"; do
    playlist+=("$MUSIC_DIR/$track")
  done

  # Auto-queue logic when exactly one track is selected
  if [ "${#selected_tracks[@]}" -eq 1 ]; then
    selected_track_path="${playlist[0]}"
    album_dir=$(dirname "$selected_track_path")

    if [ "$auto_mode" = "artist" ]; then
      artist_dir=$(dirname "$album_dir")
      # Ensure safety constraints to avoid traversing flat configurations to root directories
      if [ "$artist_dir" != "$MUSIC_DIR" ] && [[ "$artist_dir" == "$MUSIC_DIR"/* ]]; then
        mapfile -t artist_tracks < <(fd -L -e opus -e flac -e mp3 -e wav -e m4a . -- "$artist_dir" | sort -V || true)
        for track in "${artist_tracks[@]}"; do
          if [ "$track" != "$selected_track_path" ]; then
            playlist+=("$track")
          fi
        done
        auto_appended=true
      fi
    elif [ "$auto_mode" = "album" ]; then
      if [ -d "$album_dir" ]; then
        mapfile -t album_tracks < <(fd -L -e opus -e flac -e mp3 -e wav -e m4a --max-depth 1 . -- "$album_dir" | sort -V || true)
        for track in "${album_tracks[@]}"; do
          if [ "$track" != "$selected_track_path" ]; then
            playlist+=("$track")
          fi
        done
        auto_appended=true
      fi
    fi
  fi
fi

# Define base MPV parameters
mpv_args=(
  "--no-resume-playback"
  "--term-osd-bar"
  "--msg-color"
  "--msg-level=playlist=error,file=error"
  "--display-tags="
  "--loop-file=no"
  "--loop-playlist=no"
)

# Window configuration
if [ "$gui_mode" = "true" ]; then
  mpv_args+=("--force-window=yes")
else
  mpv_args+=("--no-video")
fi

# Shuffle configuration
# If the queue was auto-appended and shuffle is enabled, we keep the first track 
# in place (so playback starts instantly on your selection) and shuffle the rest.
if [ "$shuffle" = "true" ] && [ "${#playlist[@]}" -gt 1 ]; then
  if [ "$auto_appended" = "true" ]; then
    mapfile -t shuffled_rest < <(printf "%s\n" "${playlist[@]:1}" | shuf || true)
    playlist=("${playlist[0]}" "${shuffled_rest[@]}")
    mpv_args+=("--no-shuffle")
  else
    mpv_args+=("--shuffle")
  fi
else
  mpv_args+=("--no-shuffle")
fi

# Generate the custom terminal player details safely using nested conditional 
# statements, completely preventing "(error)" outputs for missing metadata.
# shellcheck disable=SC2154
term_msg="
${C_GREEN}\${media-title}${C_RESET}
\${?metadata/artist:${C_CYAN}\${metadata/artist}\${?metadata/album:${C_GRAY} on ${C_WHITE}\${metadata/album}}}\${!metadata/artist:\${?metadata/album:${C_CYAN}\${metadata/album}}}${C_RESET}
\${?metadata/date:${C_GOLD}\${metadata/date}\${?metadata/genre: ${C_GRAY}• ${C_MAGENTA}\${metadata/genre}}}\${!metadata/date:\${?metadata/genre:${C_MAGENTA}\${metadata/genre}}}${C_RESET}"

mpv_args+=("--term-playing-msg=$term_msg")

# Visual Terminal Logs
printf '\n%s🎵 Launching Player...%s\n' "${C_PURPLE}" "${C_RESET}"
printf '%sQueue:%s %s track(s)\n' "${C_GRAY}" "${C_RESET}" "${#playlist[@]}"
if [ "$gui_mode" = "true" ]; then
  printf '%sMode:%s  Visual (Press [p] in visual window to view playlist)\n\n' "${C_GRAY}" "${C_RESET}"
else
  printf '%sMode:%s  Terminal (Use active terminal keys to pause/skip/exit)\n\n' "${C_GRAY}" "${C_RESET}"
fi

# Execute
mpv "${mpv_args[@]}" "${playlist[@]}"
