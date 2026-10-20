#!/usr/bin/env bash
# zip2opus: import music archives into the Opus library. Wrapped as a
# command by zip2opus.nix, which puts ffmpeg, opustags and unar on
# PATH (shellchecked at build time by writeShellApplication).

set -euo pipefail
shopt -s nullglob

# --- Configuration ---
SOURCE_DIR="/media/fun"
LIBRARY_DIR="/media/fun/music"
# ---------------------

# Source formats that get imported. Everything except Opus is
# transcoded; Opus files are copied bit-perfect.
AUDIO_GLOBS=(
  -iname '*.flac' -o -iname '*.opus' -o -iname '*.m4a' -o -iname '*.mp3'
  -o -iname '*.ogg' -o -iname '*.oga' -o -iname '*.wav'
  -o -iname '*.aif' -o -iname '*.aiff' -o -iname '*.wma'
)

find_audio() {
  # find_audio <dir> [extra find args, e.g. -print0]
  local dir="$1"
  shift
  find "$dir" -type f \( "${AUDIO_GLOBS[@]}" \) \
    ! -name '._*' ! -path '*/__MACOSX/*' "$@"
}

tmp_path=""

cleanup() {
  if [[ -n "${tmp_path-}" && -f "$tmp_path" ]]; then
    rm -f "$tmp_path"
  fi
  if [[ -n "${temp_dir-}" && -d "$temp_dir" ]]; then
    rm -rf "$temp_dir"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

sanitize() {
  # Filesystem-safe component: also neutralizes characters that are
  # illegal on exFAT/NTFS, since the library often lives on USB media.
  local value
  value=$(printf '%s' "$1" | tr '\n\r\t' '   ' | sed 's/[\/:*?"<>|]/_/g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//;s/\.*$//')

  # DOS device names are reserved on Windows filesystems even when the
  # directory is created from Linux.
  local upper="${value^^}"
  case "$upper" in
    CON | PRN | AUX | NUL | COM[1-9] | LPT[1-9]) value="${value}_" ;;
  esac

  printf '%s' "$value"
}

# Truncate a path component to a byte budget. Filesystem component
# limits are in bytes (commonly 255), and long titles otherwise make
# ffmpeg or mv fail with ENAMETOOLONG.
truncate_bytes() {
  local value="$1"
  local max_bytes="$2"
  local byte_count
  byte_count=$(printf '%s' "$value" | wc -c)
  if [ "$byte_count" -gt "$max_bytes" ]; then
    printf '%s' "$value" | head -c "$max_bytes"
  else
    printf '%s' "$value"
  fi
}

# Folder artist for an album. Semicolon and double-slash are treated as
# multi-artist separators; commas and single slashes are left alone so
# names such as AC/DC and Earth, Wind & Fire are not truncated.
folder_artist_name() {
  local value="$1"
  value="${value%%;*}"
  if [[ "$value" == *" // "* ]]; then
    value="${value%% // *}"
  fi
  printf '%s' "$value" | sed 's/^ *//;s/ *$//'
}

disc_from_path() {
  local full_path="$1"
  local rel_path="${full_path#"$temp_dir"/}"
  local dir_path="${rel_path%/*}"
  if [[ "$dir_path" == "$rel_path" ]]; then
    return 0
  fi

  local dir_lc
  dir_lc=$(printf '%s' "$dir_path" | tr '[:upper:]' '[:lower:]')
  if [[ "$dir_lc" =~ (^|[^a-z0-9])(disc|disk|cd)[[:space:]_-]*([0-9]+)([^0-9]|$) ]]; then
    printf '%s' "${BASH_REMATCH[3]}"
  fi
}

disc_from_filename() {
  local base="${1##*/}"
  local stem="${base%.*}"
  local stem_lc
  stem_lc=$(printf '%s' "$stem" | tr '[:upper:]' '[:lower:]')
  if [[ "$stem_lc" =~ ^(disc|disk|cd)[[:space:]_-]*([0-9]+)([[:space:]_-]|$) ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
  elif [[ "$stem_lc" =~ ^([0-9]{1,2})[-.]([0-9]{1,3})([[:space:]_-]|$) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

durations_match() {
  local first="$1"
  local second="$2"
  if ! [[ "$first" =~ ^[0-9]+([.][0-9]+)?$ && "$second" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    return 1
  fi
  awk -v a="$first" -v b="$second" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d < 1.5) }'
}

# Single-pass metadata tag reader using native ffprobe.
# Sets the globals raw_title/raw_track/raw_disc/raw_artist/raw_album
# and raw_album_artist. Track artist and album artist deliberately stay
# separate: compilations must keep their per-track performers.
load_tags() {
  local file="$1"
  raw_title=""
  raw_track=""
  raw_disc=""
  raw_artist=""
  raw_album=""
  raw_album_artist=""

  while IFS= read -r line; do
    line=$(printf '%s' "$line" | tr -d '\r')
    if [[ "$line" =~ ^TAG:([^=]+)=(.*)$ ]]; then
      local key
      key=$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
      local val="${BASH_REMATCH[2]}"
      case "$key" in
        title) raw_title="$val" ;;
        track) raw_track="$val" ;;
        disc | discnumber | disk | disknumber) raw_disc="$val" ;;
        artist) raw_artist="$val" ;;
        albumartist | album_artist) raw_album_artist="$val" ;;
        album) raw_album="$val" ;;
      esac
    fi
  done < <(ffprobe -v error -show_entries format_tags -of default=noprint_wrappers=1 "$file" 2>/dev/null)
}

get_opus_source_tag() {
  local file="$1"
  opustags --list "$file" 2>/dev/null | grep -i "^SOURCE_FILENAME=" | cut -d= -f2- || true
}

# already_imported <output path>: succeeds when that file already
# holds the current source track ($audio_filename), proven by its
# SOURCE_FILENAME tag. A matching duration (within 1.5s) is the
# fallback: it covers files imported before that tag existed, source
# files renamed since the import, and format upgrades such as an MP3
# archive replaced by the same album as FLAC. Sets import_match to
# "tag" or "duration" for the caller's skip message.
already_imported() {
  import_match=""
  local out="$1"
  [ -f "$out" ] || return 1

  local src
  src=$(get_opus_source_tag "$out")
  if [ -n "$src" ]; then
    if [ "$src" = "$audio_filename" ]; then
      import_match="tag"
    elif [ -n "${src%.*}" ] && [ "${src%.*}" = "${audio_filename%.*}" ]; then
      # Same stem, different extension: an MP3 import and a later FLAC
      # copy of the same track are the same import, not a duplicate.
      import_match="tag"
    fi
  fi

  if [ -z "$import_match" ]; then
    local od
    od=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$out" 2>/dev/null || true)
    if durations_match "$dur_audio" "$od"; then
      import_match="duration"
    fi
  fi

  [ -n "$import_match" ]
}

for cmd in ffmpeg ffprobe opustags unar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Missing dependency: $cmd (expected from the Nix runtime inputs)"
    exit 1
  fi
done

cd "$SOURCE_DIR" || { echo "❌ Cannot change directory to '$SOURCE_DIR'"; exit 1; }
mkdir -p "$LIBRARY_DIR"

echo "📂 Scanning for archives in $SOURCE_DIR..."

for archive in *.[zZ][iI][pP] *.7[zZ] *.[rR][aA][rR]; do
  [ -e "$archive" ] || continue

  echo "📦 Processing: $archive"
  temp_dir=$(mktemp -d)

  if ! unar -o "$temp_dir" -f -D -q "$archive"; then
    echo "   ❌ Extraction failed. Skipping."
    rm -rf "$temp_dir"
    continue
  fi

  # Choose the file that describes the album. Prefer one carrying an
  # album artist (the reliable identity for compilations and
  # soundtracks); otherwise use the first tagged file in sorted order,
  # so the choice does not depend on filesystem order.
  first_audio=""
  tagged_audio=""
  any_audio=""
  while IFS= read -r -d '' file; do
    if [ -z "$any_audio" ]; then
      any_audio="$file"
    fi
    load_tags "$file"
    if [ -n "$raw_album" ]; then
      if [ -n "$raw_album_artist" ]; then
        first_audio="$file"
        break
      fi
      if [ -z "$tagged_audio" ] && [ -n "$raw_artist" ]; then
        tagged_audio="$file"
      fi
    fi
  done < <(find_audio "$temp_dir" -print0 | LC_ALL=C sort -z)

  if [ -z "$first_audio" ]; then
    first_audio="$tagged_audio"
  fi

  # Fallback to the first available audio file if no file has usable tags
  if [ -z "$first_audio" ]; then
    first_audio="$any_audio"
  fi
  if [ -n "$first_audio" ]; then
    load_tags "$first_audio"
  fi

  if [ -z "$first_audio" ]; then
    echo "   ⚠️  No supported audio files found in archive. Skipping."
    rm -rf "$temp_dir"
    continue
  fi

  echo "   🔍 Reading album metadata..."
  archive_artist=""
  archive_album=""
  base_name="${archive%.*}"
  if [[ "$base_name" == *" - "* ]]; then
    archive_artist="${base_name%% - *}"
    archive_album="${base_name#* - }"
  else
    archive_artist="$base_name"
  fi

  # Fill only the fields that are actually missing. A valid artist tag
  # must survive just because the album tag is absent, and vice versa.
  had_album_tags=false
  if [ -n "$raw_album" ] && { [ -n "$raw_artist" ] || [ -n "$raw_album_artist" ]; }; then
    had_album_tags=true
  fi
  if [ -z "$raw_artist" ] && [ -z "$raw_album_artist" ]; then
    raw_artist="$archive_artist"
  fi
  if [ -z "$raw_album" ]; then
    raw_album="$archive_album"
  fi
  if [ -z "$raw_album_artist" ]; then
    raw_album_artist="$raw_artist"
  fi

  folder_artist_raw="$raw_album_artist"
  if [ -z "$folder_artist_raw" ]; then
    folder_artist_raw="$raw_artist"
  fi
  primary_artist=$(folder_artist_name "$folder_artist_raw")
  clean_artist=$(truncate_bytes "$(sanitize "$primary_artist")" 200)
  clean_album=$(truncate_bytes "$(sanitize "$raw_album")" 200)

  if [ "$had_album_tags" = true ]; then
    echo "   ✅ Metadata Found: '$clean_artist' (Folder) / '$folder_artist_raw' (Tags) - '$clean_album'"
  else
    echo "   ⚠️  Tags incomplete. Supplemented from the archive name where needed."
  fi

  # Album-level tags, used as fallback for tracks that lack their own.
  # The artist fallback is the album identity (album artist when the
  # album carries one), not the representative track's performer.
  album_tag_artist="$folder_artist_raw"
  album_tag_album_artist="$raw_album_artist"
  album_tag_album="$raw_album"

  [ -n "$clean_artist" ] || clean_artist="Unknown Artist"
  [ -n "$clean_album" ] || clean_album="Unknown Album"

  target_dir="$LIBRARY_DIR/$clean_artist/$clean_album"
  mkdir -p "$target_dir"

  # --- PRESERVE NFO & COVER ---
  nfo_source=$(find "$temp_dir" -type f -iname "*.nfo" -print -quit)
  if [ -n "$nfo_source" ]; then
    cp "$nfo_source" "$target_dir/album.nfo"
    echo "   📄 Preserved: album.nfo"
  fi

  external_cover=$(find "$temp_dir" -type f \( -iname 'cover.jpg' -o -iname 'cover.jpeg' -o -iname 'cover.png' -o -iname 'folder.jpg' -o -iname 'folder.png' -o -iname 'front.jpg' -o -iname 'album.jpg' \) -print -quit)
  if [ -n "$external_cover" ]; then
    extension="${external_cover##*.}"
    cp "$external_cover" "$target_dir/cover.${extension}"
    echo "   🖼️ Preserved: cover.${extension}"
  fi
  # ----------------------------

  # Pre-scan: does this album actually span multiple discs? Only then
  # do file names get a disc prefix. A lone "Disc 1/1" tag (every TIDAL
  # file carries one) must not rename single-disc albums.
  album_multi_disc=false
  while IFS= read -r -d '' scan_file; do
    load_tags "$scan_file"
    scan_tag_disc="${raw_disc%%/*}"
    if [[ "$scan_tag_disc" =~ ([0-9]+) ]]; then
      scan_tag_disc="${BASH_REMATCH[1]}"
    else
      scan_tag_disc=""
    fi
    scan_total=""
    if [[ "$raw_disc" == */* ]]; then scan_total="${raw_disc##*/}"; fi

    # Physical layout wins over disc tags: rippers sometimes stamp
    # every file DISCNUMBER=1 while the folders (or 1-01 style file
    # names) still separate the discs.
    scan_disc=$(disc_from_path "$scan_file")
    if [ -z "$scan_disc" ]; then
      scan_disc=$(disc_from_filename "$scan_file")
    fi
    if [ -z "$scan_disc" ]; then
      scan_disc="$scan_tag_disc"
    fi

    if [[ "$scan_disc" =~ ^[0-9]+$ ]] && [ "$((10#$scan_disc))" -gt 1 ]; then
      album_multi_disc=true
      break
    fi
    if [[ "$scan_total" =~ ^[0-9]+$ ]] && [ "$((10#$scan_total))" -gt 1 ]; then
      album_multi_disc=true
      break
    fi
  done < <(find_audio "$temp_dir" -print0 | LC_ALL=C sort -z)

  # Process all supported audio files in sorted (deterministic) order
  while IFS= read -r -d '' audio_path; do
    audio_filename=$(basename "$audio_path")
    tmp_path=""

    # Load all track tags at once
    load_tags "$audio_path"

    # Tracks without their own artist/album fields inherit the
    # album-level values field by field.
    [ -n "$raw_artist" ] || raw_artist="$album_tag_artist"
    [ -n "$raw_album_artist" ] || raw_album_artist="$album_tag_album_artist"
    [ -n "$raw_album" ] || raw_album="$album_tag_album"

    effective_artist="$raw_artist"
    if [ -z "$effective_artist" ]; then
      effective_artist="$raw_album_artist"
    fi
    effective_album_artist="$raw_album_artist"
    if [ -z "$effective_album_artist" ]; then
      effective_album_artist="$effective_artist"
    fi
    if [ -z "$effective_artist" ]; then
      effective_artist="$effective_album_artist"
    fi

    # --- STRUCTURAL DISC NUMBER (folder or 1-01 style file name) ---
    # Physical layout wins over the disc tag, which some rippers stamp
    # as 1 on every file of a multi-disc set.
    path_disc=$(disc_from_path "$audio_path")
    if [ -n "$path_disc" ]; then
      raw_disc="$path_disc"
    else
      filename_disc=$(disc_from_filename "$audio_path")
      if [ -n "$filename_disc" ]; then
        raw_disc="$filename_disc"
      fi
    fi

    # --- EXTRACT TRACK NUMBER FROM FILENAME ---
    # Only 1-3 digit numbers followed by a delimiter count. A leading
    # release year (1999 - ...) is not a track number.
    filename_track=""
    filename_stem="${audio_filename%.*}"
    if [[ "$filename_stem" =~ ^([0-9]{1,2})[-.]([0-9]{1,3})([[:space:]_-]|$) ]]; then
      filename_track="${BASH_REMATCH[2]}"
    elif [[ "$filename_stem" =~ ^([0-9]{1,3})([[:space:]_. -]|$) ]]; then
      filename_track="${BASH_REMATCH[1]}"
    fi

    # --- SANITY CHECK FOR SEQUENCE MISMATCH IN FLAT ARCHIVES ---
    if [ -n "$raw_track" ] && [ -n "$filename_track" ]; then
      clean_raw_track="${raw_track%%/*}"
      if [[ "$clean_raw_track" =~ ^[0-9]+$ ]] && [[ "$filename_track" =~ ^[0-9]+$ ]]; then
        if [ $((10#$clean_raw_track)) -ne $((10#$filename_track)) ] && { [ -z "$raw_disc" ] || [ "$raw_disc" = "0" ]; }; then
          raw_track="$filename_track"
        fi
      fi
    fi

    # --- FILENAME PARSING FALLBACK ---
    if [ -z "$raw_track" ] || [ -z "$raw_title" ]; then
      parsed_track=""
      parsed_title=""
      rest="$filename_stem"
      if [[ "$rest" =~ ^(19|20)[0-9]{2}[[:space:]]+-[[:space:]]+([0-9]{1,3})[[:space:]._-]+(.+)$ ]]; then
        # Release year prefix, then the real track number
        parsed_track="${BASH_REMATCH[2]}"
        rest="${BASH_REMATCH[3]}"
      elif [[ "$rest" =~ ^([0-9]{1,2})[-.]([0-9]{1,3})[[:space:]._-]+(.+)$ ]]; then
        # Disc-track prefix such as 1-01 or 2.03
        parsed_track="${BASH_REMATCH[2]}"
        rest="${BASH_REMATCH[3]}"
      elif [[ "$rest" =~ ^([0-9]{1,3})[[:space:]._-]+(.+)$ ]]; then
        parsed_track="${BASH_REMATCH[1]}"
        rest="${BASH_REMATCH[2]}"
      fi
      if [[ "$rest" == *" - "* ]]; then
        # First separator wins: in "Artist - Title - Remix" the title
        # is "Title - Remix", not just the last segment.
        parsed_title="${rest#* - }"
      elif [ "$rest" != "$filename_stem" ] || ! [[ "$rest" =~ ^[0-9]+$ ]]; then
        parsed_title="$rest"
      fi
      if [ -z "$raw_track" ]; then
        raw_track="$parsed_track"
      fi
      if [ -z "$raw_title" ]; then
        raw_title="$parsed_title"
      fi
    fi
    # -------------------------------------

    clean_track="${raw_track%%/*}"
    if [[ "$clean_track" =~ ^[0-9]+$ ]]; then
      printf -v clean_track "%02d" "$((10#$clean_track))"
    fi

    clean_disc="${raw_disc%%/*}"
    if [[ "$clean_disc" =~ ([0-9]+) ]]; then
      clean_disc=$((10#${BASH_REMATCH[1]}))
    else
      clean_disc=0
    fi

    clean_title=$(truncate_bytes "$(sanitize "$raw_title")" 200)

    # Disc prefix only for genuinely multi-disc albums. legacy_name is
    # the name older versions of this script would have produced; it is
    # still checked on import so those files are recognized, not duped.
    legacy_name=""
    if [ -n "$clean_title" ]; then
      if [ -n "$clean_track" ]; then
        if [ "$album_multi_disc" = true ] && [[ "$clean_disc" =~ ^[0-9]+$ ]] && [ "$clean_disc" -gt 0 ]; then
          opus_name="${clean_disc}-${clean_track} - ${clean_title}.opus"
        else
          opus_name="${clean_track} - ${clean_title}.opus"
          if [[ "$clean_disc" =~ ^[0-9]+$ ]] && [ "$clean_disc" -gt 0 ]; then
            legacy_name="${clean_disc}-${opus_name}"
          fi
        fi
      else
        opus_name="${clean_title}.opus"
      fi
    else
      fallback_stem=$(truncate_bytes "$(sanitize "${audio_filename%.*}")" 240)
      if [ -z "$fallback_stem" ]; then
        fallback_stem="untitled"
      fi
      opus_name="${fallback_stem}.opus"
    fi

    base_no_ext="${opus_name%.opus}"

    # An already-imported copy may sit under the plain name or under
    # the legacy disc-prefixed name; check both before converting.
    declare -a name_candidates=("$opus_name")
    if [ -n "$legacy_name" ]; then
      name_candidates+=("$legacy_name")
    fi

    dur_audio=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio_path" 2>/dev/null || true)

    report_skip() {
      if [ "$import_match" = "duration" ]; then
        echo "   ⏭️  Skipping (already converted/imported / legacy): $(basename "$1")"
      else
        echo "   ⏭️  Skipping (already converted/imported): $(basename "$1")"
      fi
    }

    skip_file=false
    for cand in "${name_candidates[@]}"; do
      current_out="$target_dir/$cand"
      if already_imported "$current_out"; then
        report_skip "$current_out"
        skip_file=true
        break
      fi
    done

    # First free name: the plain name, then " (2)", " (3)", ...
    # The plain name was already probed in the candidate loop above,
    # so only suffixed siblings need an already_imported check here.
    final_path=""
    if [ "$skip_file" = false ]; then
      current_out="$target_dir/$opus_name"
      if [ ! -e "$current_out" ]; then
        final_path="$current_out"
      else
        counter=1
        while [ -z "$final_path" ]; do
          counter=$((counter + 1))
          current_out="$target_dir/${base_no_ext} (${counter}).opus"
          if [ ! -e "$current_out" ]; then
            final_path="$current_out"
          elif already_imported "$current_out"; then
            report_skip "$current_out"
            skip_file=true
            break
          fi
        done
      fi
    fi

    if [ "$skip_file" = true ]; then continue; fi
    tmp_path="$target_dir/.tmp_$$_$(basename "$final_path")"
    rm -f "$tmp_path"

    # Handle the file copy or transcode branch depending on original format
    file_ext="${audio_filename##*.}"
    file_ext_lc=$(printf '%s' "$file_ext" | tr '[:upper:]' '[:lower:]')

    if [ "$file_ext_lc" = "opus" ]; then
      # Copy file directly to avoid generational loss from re-encoding
      if ! cp "$audio_path" "$tmp_path"; then
        echo "   ❌ Copy Failed: $audio_filename"
        rm -f "$tmp_path"
        continue
      fi
    else
      # Transcode to high-quality VBR Opus
      if ! ffmpeg \
        -nostdin -hide_banner -loglevel error \
        -i "$audio_path" \
        -c:a libopus -b:a 256k -vbr on -compression_level 10 \
        -vn -map_metadata 0 \
        "$tmp_path"; then
        echo "   ❌ Encoding Failed: $audio_filename"
        rm -f "$tmp_path"
        continue
      fi
    fi

    # --- TAG INJECTION (best effort: never abort the whole run) ---
    declare -a tags_args=("--in-place")
    tags_args+=("--set" "SOURCE_FILENAME=$audio_filename")
    if [ -n "$effective_artist" ]; then
      tags_args+=("--set" "ARTIST=$effective_artist")
    fi
    if [ -n "$effective_album_artist" ]; then
      tags_args+=("--set" "ALBUMARTIST=$effective_album_artist")
    fi
    if [ -n "$raw_album" ]; then
      tags_args+=("--set" "ALBUM=$raw_album")
    fi
    if [ -n "$raw_title" ]; then
      tags_args+=("--set" "TITLE=$raw_title")
    fi
    if [ -n "$clean_track" ]; then
      tags_args+=("--set" "TRACKNUMBER=$clean_track")
    fi
    if [[ "$clean_disc" =~ ^[0-9]+$ ]] && [ "$clean_disc" -gt 0 ]; then
      tags_args+=("--set" "DISCNUMBER=$clean_disc")
    fi
    if ! opustags "${tags_args[@]}" "$tmp_path" >/dev/null 2>&1; then
      echo "   ⚠️  Tagging failed: $(basename "$tmp_path")"
    fi
    # Drop the multi-KB TIDAL JSON blob that -map_metadata drags along
    opustags --in-place --delete TIDAL_DATA "$tmp_path" >/dev/null 2>&1 || true

    # --- COVER INJECTION ---
    if [ -n "$external_cover" ] && [ -f "$external_cover" ]; then
      opustags --in-place --set-cover "$external_cover" "$tmp_path" >/dev/null 2>&1 || true
    else
      cover_temp="$temp_dir/cover_art.jpg"
      if ffmpeg -nostdin -hide_banner -loglevel error \
        -i "$audio_path" -an -c:v mjpeg -q:v 5 -f image2 -y "$cover_temp" >/dev/null 2>&1; then
        if [ -s "$cover_temp" ]; then
          opustags --in-place --set-cover "$cover_temp" "$tmp_path" >/dev/null 2>&1 || true
          # Folder-based players need a cover file, not just embedded art
          if [ ! -f "$target_dir/cover.jpg" ] && cp "$cover_temp" "$target_dir/cover.jpg"; then
            echo "   🖼️ Preserved: cover.jpg (from embedded art)"
          fi
        fi
      fi
      rm -f "$cover_temp"
    fi

    # --- LYRICS PRESERVATION (named after the final opus file) ---
    lrc_source="${audio_path%.*}.lrc"
    [ -f "$lrc_source" ] || lrc_source="${audio_path%.*}.LRC"
    if [ -f "$lrc_source" ]; then
      cp "$lrc_source" "$target_dir/$(basename "${final_path%.opus}").lrc"
    fi

    mv "$tmp_path" "$final_path"
    tmp_path=""
    echo "   ✅ Converted/Imported: $(basename "$final_path")"

  done < <(find_audio "$temp_dir" -print0 | LC_ALL=C sort -z)

  rm -rf "$temp_dir"
  echo "---------------------------------------------------"
done

echo "🎉 Finished."
