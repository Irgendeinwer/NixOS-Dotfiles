#!/usr/bin/env python3
import argparse
import hashlib
import json
import multiprocessing as mp
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

AUDIO_EXTS = ('.opus', '.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac')
USER_AGENT = 'NixOS-Lrclib-Publisher/1.0 (https://github.com/Irgendeinwer/NixOS-Dotfiles)'


def get_audio_info(audio_path):
    if not audio_path or not os.path.exists(audio_path):
        return None, {}
    if not shutil.which('ffprobe'):
        return None, {}

    cmd = [
        'ffprobe',
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        audio_path,
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=10)
        data = json.loads(res.stdout)

        fmt = data.get('format', {})
        duration = round(float(fmt['duration'])) if 'duration' in fmt else None

        tags = {}
        # Audio stream tags & fallback duration (common in Opus/AAC/M4A)
        for stream in data.get('streams', []):
            if stream.get('codec_type') != 'audio':
                continue
            for k, v in stream.get('tags', {}).items():
                tags[k.lower()] = v
            if not duration and 'duration' in stream:
                try:
                    duration = round(float(stream['duration']))
                except (ValueError, TypeError):
                    pass

        # Container tags take precedence
        for k, v in fmt.get('tags', {}).items():
            tags[k.lower()] = v

        return duration, tags
    except Exception:
        return None, {}


def parse_lrc(lrc_path):
    if not lrc_path or not os.path.exists(lrc_path):
        return {}, '', ''

    with open(lrc_path, 'r', encoding='utf-8-sig', errors='replace') as f:
        lines = f.readlines()

    meta = {}
    timed_entries = []

    tag_aliases = {
        'title': 'ti',
        'artist': 'ar',
        'album': 'al',
        'author': 'au',
    }

    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue

        # Match specific LRC metadata tags and their aliases
        m_tag = re.match(r'^\[(ti|title|ar|artist|al|album|au|author|by|length|offset|re|ve)\s*:\s*(.*)\]$', line, re.IGNORECASE)
        if m_tag:
            key = m_tag.group(1).lower()
            key = tag_aliases.get(key, key)
            meta[key] = m_tag.group(2).strip()
            continue

        time_tags = re.findall(r'\[(\d+):(\d{2}(?:\.\d{1,3})?)\]', line)
        if time_tags:
            # Strip all leading bracket timestamps, even if space-separated
            lyric_text = re.sub(r'^(\s*\[\d+:\d{2}(?:\.\d{1,3})?\]\s*)+', '', line).strip()
            plain_text = re.sub(r'<\d+:\d{2}(?:\.\d{1,3})?>', '', lyric_text).strip()

            for m, s in time_tags:
                total_sec = int(m) * 60 + float(s)
                synced_line = f'[{int(m):02d}:{float(s):05.2f}]{lyric_text}'
                timed_entries.append((total_sec, synced_line, plain_text))

    timed_entries.sort(key=lambda x: x[0])

    synced_lyrics = '\n'.join(entry[1] for entry in timed_entries)
    plain_lyrics = '\n'.join(entry[2] for entry in timed_entries if entry[2])

    return meta, synced_lyrics, plain_lyrics


def parse_duration_str(dur_str):
    if not dur_str:
        return None
    try:
        parts = dur_str.strip().split(':')
        if len(parts) == 1:
            return round(float(parts[0]))
        elif len(parts) == 2:
            return round(int(parts[0]) * 60 + float(parts[1]))
        elif len(parts) == 3:
            return round(int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2]))
    except ValueError:
        return None
    return None


def find_file_case_insensitive(dir_name, base_name, valid_exts):
    if not os.path.isdir(dir_name):
        return None
    base_name_lower = base_name.lower()
    valid_exts_lower = [e.lower() for e in valid_exts]
    for f in os.listdir(dir_name):
        f_base, f_ext = os.path.splitext(f)
        if f_base.lower() == base_name_lower and f_ext.lower() in valid_exts_lower:
            return os.path.join(dir_name, f)
    return None


def select_from_list(items, prompt_text):
    if len(items) == 1:
        return items[0]
    if not sys.stdin.isatty():
        sys.exit('[-] Multiple files found, but not running in an interactive terminal (TTY). Please specify the file explicitly.')
    print(f'[?] {prompt_text}')
    for i, f in enumerate(items, 1):
        print(f'    [{i}] {os.path.basename(f)}')
    choice = input('Select a number: ').strip()
    try:
        idx = int(choice) - 1
        if idx < 0 or idx >= len(items):
            raise IndexError()
        return items[idx]
    except Exception:
        sys.exit('[-] Invalid selection.')


def find_files(target_path, is_instrumental=False):
    if not os.path.exists(target_path):
        sys.exit(f"[-] Path '{target_path}' does not exist!")

    lrc_file = None
    audio_file = None

    if os.path.isfile(target_path):
        ext = os.path.splitext(target_path)[1].lower()
        dir_name = os.path.dirname(target_path) or '.'
        base_name = os.path.splitext(os.path.basename(target_path))[0]

        if ext == '.lrc':
            lrc_file = target_path
            audio_file = find_file_case_insensitive(dir_name, base_name, AUDIO_EXTS)
            if not audio_file:
                # Fallback: if there's only 1 audio file in that folder, use it
                candidates = [os.path.join(dir_name, f) for f in os.listdir(dir_name) if os.path.splitext(f)[1].lower() in AUDIO_EXTS]
                if len(candidates) == 1:
                    audio_file = candidates[0]
        elif ext in AUDIO_EXTS:
            audio_file = target_path
            lrc_file = find_file_case_insensitive(dir_name, base_name, ['.lrc'])
            if not lrc_file and not is_instrumental:
                candidates = [os.path.join(dir_name, f) for f in os.listdir(dir_name) if f.lower().endswith('.lrc')]
                if len(candidates) == 1:
                    lrc_file = candidates[0]
            if not lrc_file and not is_instrumental:
                sys.exit(
                    f"[-] No matching LRC file found for '{target_path}'!\n"
                    f"    (If this is an instrumental track, please use --instrumental)."
                )
        else:
            sys.exit(f'[-] Unsupported file type: {target_path}')

    elif os.path.isdir(target_path):
        lrcs = [
            os.path.join(target_path, f)
            for f in os.listdir(target_path)
            if f.lower().endswith('.lrc')
        ]

        if lrcs:
            lrc_file = select_from_list(lrcs, 'Multiple .lrc files found:')
            base_name = os.path.splitext(os.path.basename(lrc_file))[0]
            audio_file = find_file_case_insensitive(target_path, base_name, AUDIO_EXTS)
            if not audio_file:
                candidates = [os.path.join(target_path, f) for f in os.listdir(target_path) if os.path.splitext(f)[1].lower() in AUDIO_EXTS]
                if len(candidates) == 1:
                    audio_file = candidates[0]
                elif len(candidates) > 1 and sys.stdin.isatty():
                    audio_file = select_from_list(candidates, 'Select matching audio file:')
        else:
            if is_instrumental:
                audios = [
                    os.path.join(target_path, f)
                    for f in os.listdir(target_path)
                    if os.path.splitext(f)[1].lower() in AUDIO_EXTS
                ]
                if not audios:
                    sys.exit(f"[-] No audio file found in '{target_path}' for instrumental track!")
                audio_file = select_from_list(audios, 'Multiple audio files found (instrumental):')
            else:
                sys.exit(
                    f"[-] No .lrc file found in '{target_path}'!\n"
                    f"    (If this is an instrumental track, please use --instrumental)."
                )

    return lrc_file, audio_file


def _pow_worker(prefix_bytes, target_bytes, worker_id, num_workers, batch_size, stop_event, found_nonce):
    stride = num_workers * batch_size
    nonce_start = worker_id * batch_size
    sha256 = hashlib.sha256

    try:
        while not stop_event.is_set():
            batch_end = nonce_start + batch_size
            for nonce in range(nonce_start, batch_end):
                if sha256(prefix_bytes + b'%d' % nonce).digest() <= target_bytes:
                    with found_nonce.get_lock():
                        if found_nonce.value == -1:
                            found_nonce.value = nonce
                    stop_event.set()
                    return
            nonce_start += stride
    except KeyboardInterrupt:
        pass


def solve_challenge(prefix, target_hex):
    target_bytes = bytes.fromhex(target_hex)
    prefix_bytes = prefix.encode('utf-8')
    num_workers = max(1, os.cpu_count() or 4)

    start_time = time.time()
    print(f'[*] Solving Proof-of-Work challenge using {num_workers} workers...', end='', flush=True)

    stop_event = mp.Event()
    found_nonce = mp.Value('q', -1)
    workers = []

    for i in range(num_workers):
        p = mp.Process(
            target=_pow_worker,
            args=(prefix_bytes, target_bytes, i, num_workers, 50000, stop_event, found_nonce),
            daemon=True,
        )
        p.start()
        workers.append(p)

    try:
        while not stop_event.wait(timeout=0.1):
            if not any(p.is_alive() for p in workers):
                break
    except KeyboardInterrupt:
        stop_event.set()
        for p in workers:
            p.terminate()
        sys.exit('\n[-] Aborted by user.')
    finally:
        for p in workers:
            p.join(timeout=0.2)

    nonce = found_nonce.value
    if nonce == -1:
        sys.exit('\n[-] Failed to solve challenge: workers exited without solution.')

    elapsed = time.time() - start_time
    print(f' done! ({elapsed:.2f}s, Nonce: {nonce})')
    return str(nonce)


def main():
    parser = argparse.ArgumentParser(description='Universal LRCLIB Lyrics Uploader')
    parser.add_argument(
        'path',
        nargs='?',
        default='.',
        help='Path to .lrc file, audio file, or directory (default: .)',
    )
    parser.add_argument('-t', '--track', help='Override / specify track title')
    parser.add_argument('-a', '--artist', help='Override / specify artist name')
    parser.add_argument('-b', '--album', help='Override / specify album name')
    parser.add_argument('-d', '--duration', type=int, help='Override duration in seconds')
    parser.add_argument(
        '--instrumental',
        action='store_true',
        help='Explicitly mark track as instrumental without lyrics',
    )
    parser.add_argument('-y', '--yes', action='store_true', help='Skip confirmation prompt')
    parser.add_argument('-n', '--dry-run', action='store_true', help='Display metadata only, do not upload')

    args = parser.parse_args()

    lrc_file, audio_file = find_files(args.path, is_instrumental=args.instrumental)

    if lrc_file:
        print(f"[+] Using LRC:     '{lrc_file}'")
    if audio_file:
        print(f"[+] Found audio:   '{audio_file}'")

    lrc_meta, synced_lyrics, plain_lyrics = parse_lrc(lrc_file)
    audio_duration, audio_tags = get_audio_info(audio_file)

    if not synced_lyrics and not plain_lyrics and not args.instrumental:
        sys.exit(
            '[-] ERROR: Neither plain nor synced lyrics could be read!\n'
            '    Upload aborted to avoid marking the track as instrumental on LRCLIB by mistake.\n'
            '    (If it really is an instrumental track, please use --instrumental).'
        )

    ref_file = lrc_file or audio_file
    raw_stem = os.path.splitext(os.path.basename(ref_file))[0] if ref_file else ''
    clean_title = re.sub(r'^\d+[\s._-]+', '', raw_stem).strip()

    track_name = (
        args.track
        or audio_tags.get('title')
        or lrc_meta.get('ti')
        or clean_title
    )
    if not track_name:
        if sys.stdin.isatty():
            track_name = input('[?] No track title found. Enter title: ').strip()
        if not track_name:
            sys.exit('[-] ERROR: Track title unknown. Please specify with -t / --track.')

    artist_name = args.artist or audio_tags.get('artist') or lrc_meta.get('ar')
    if not artist_name:
        if sys.stdin.isatty():
            artist_name = input('[?] No artist found. Enter artist: ').strip()
        if not artist_name:
            sys.exit('[-] ERROR: Artist unknown. Please specify with -a / --artist.')

    album_name = args.album or audio_tags.get('album') or lrc_meta.get('al') or ''

    duration = args.duration or audio_duration
    if not duration:
        duration = parse_duration_str(lrc_meta.get('length'))

    if not duration:
        sys.exit('[-] ERROR: Track duration could not be determined. Please specify with -d / --duration <sec>.')

    print('\n' + '=' * 45)
    print(f' Track:        {track_name}')
    print(f' Artist:       {artist_name}')
    print(f" Album:        {album_name or '(No album)'}")
    print(f' Duration:     {duration}s')
    print(f' Synced:       {len(synced_lyrics.splitlines()) if synced_lyrics else 0} lines')
    print(f' Plain:        {len(plain_lyrics.splitlines()) if plain_lyrics else 0} lines')
    print(f' Instrumental: {"Yes" if args.instrumental else "No"}')
    print('=' * 45 + '\n')

    if args.dry_run:
        print('[*] Dry run finished. Nothing uploaded.')
        return

    if not args.yes and sys.stdin.isatty():
        confirm = input('Upload to LRCLIB now? [Y/n]: ').strip().lower()
        if confirm not in ('', 'y', 'yes'):
            print('Aborted.')
            return

    print('[*] Requesting challenge from https://lrclib.net...')
    req = urllib.request.Request(
        'https://lrclib.net/api/request-challenge',
        data=b'',
        headers={'User-Agent': USER_AGENT},
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            challenge = json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode('utf-8', errors='replace')
        sys.exit(f'[-] Failed to request challenge ({e.code}): {err_msg}')
    except urllib.error.URLError as e:
        sys.exit(f'[-] Failed to request challenge: {e}')

    nonce = solve_challenge(challenge['prefix'], challenge['target'])
    publish_token = f"{challenge['prefix']}:{nonce}"

    payload = {
        'trackName': track_name,
        'artistName': artist_name,
        'albumName': album_name,
        'duration': duration,
        'plainLyrics': '' if args.instrumental else plain_lyrics,
        'syncedLyrics': '' if args.instrumental else synced_lyrics,
    }

    req_pub = urllib.request.Request(
        'https://lrclib.net/api/publish',
        data=json.dumps(payload).encode('utf-8'),
        headers={
            'Content-Type': 'application/json',
            'X-Publish-Token': publish_token,
            'User-Agent': USER_AGENT,
        },
        method='POST',
    )

    try:
        with urllib.request.urlopen(req_pub, timeout=30) as resp:
            if resp.status in (200, 201):
                print('\n[✔] Successfully published to LRCLIB!')
            else:
                print(f'[!] Status: {resp.status}')
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode('utf-8', errors='replace')
        sys.exit(f'[-] API error {e.code}: {err_msg}')
    except urllib.error.URLError as e:
        sys.exit(f'[-] Network error: {e}')


if __name__ == '__main__':
    main()
