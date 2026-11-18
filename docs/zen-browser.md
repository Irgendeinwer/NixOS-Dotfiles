# Zen Browser and existing profiles

Zen is installed through Home Manager when `custom.desktop.browsers.enable` is
on. Its package and policies are declarative; application updates and telemetry
are disabled by default, so update the browser through the flake input. An
explicit `programs.zen-browser.enable` can override that default.

## Shared configuration and ownership

`junixos` and `junixbook` keep `programs.zen-browser.configPath = ".zen"` in
`hosts/<host>/home.nix`, independently of profile adoption. They import
`modules/zen/profile.nix` and set `custom.desktop.zen.profilePath` to their own
**existing** profile directories:

| Host | Registry | Profile |
| --- | --- | --- |
| `junixos` | `~/.zen/profiles.ini` | `~/.zen/mpjpva0z.default` |
| `junixbook` | `~/.zen/profiles.ini` | `~/.zen/xtezh31k.default` |

The wrapper uses `~/.zen` and sets `MOZ_LEGACY_PROFILES=1`. Zen, not Home
Manager, owns `profiles.ini` and its other profile/install entries. The Nix
profile's `id` and `isDefault` do **not** select the active profile while the
registry is unmanaged: confirm the actual profile in `about:profiles` and the
installation entries before switching. The guard requires a regular, non-symlink
registry and a matching `[ProfileN]` entry, interpreting `Path` according to
`IsRelative`. It does not determine which registered profile Zen selects.

For a fresh install, leave `configPath` and the import in place and set
`custom.desktop.zen.profilePath = null`. This keeps the wrapper on `~/.zen`
without declaring profiles, profile links, mod reconciliation, or the extension
policy below. Let Zen create its own profile, then follow the adoption steps to
set the actual directory. See [recovery](recovery.md) for the reinstall flow.

Home Manager links `.keep`, `user.js`, and `chrome/userChrome.css` inside the
selected profile. The shared `settings.nix` contains the supplied filtered
preferences, not a full `prefs.js`; `user.js` reapplies those values when Zen
starts. The CSS and Super Url Bar color use `custom.theme.palette`, including a
fallback when the optional `bg_current_word` role is absent. The upstream
module enables userChrome loading. Mod styles are loaded by Zen, not imported
again through userChrome. Change declared settings in Nix rather than relying
on an about:config change that `user.js` will undo. Nix store files are
world-readable: never put credentials or private browser data in settings.

Bookmarks, passwords, profile databases, tabs, workspaces, pins, permissions,
other preferences, and extension storage are **not** declared by this module.
Unlisted extensions and mods are not removed or disabled. The installed
extensions' internal settings and enabled states were not part of the supplied
information, so the two profiles can still differ. Firefox Sync is not a
complete local backup.

## Extensions

`modules/zen/extensions.nix` lists 17 extension IDs in the browser-wide
`ExtensionSettings` policy, with `normal_installed` and AMO's latest-version
URL. The policy applies to **every profile launched with this Zen package**,
not just the selected profile. Zen can install or replace an XPI from AMO at
startup and then update extensions normally. The policy does not force them on:
existing enabled/disabled choices are left to the browser, and a newly installed
extension may start enabled. While the policy is active, listed extensions can
be disabled but not uninstalled in about:addons; remove a policy entry to allow
uninstallation. There is no catch-all block.

The configuration does not link extension XPIs over profile files and does
not set `profiles.*.extensions.settings`. The latter would require inventing
extension-specific settings and can alter Firefox's profile-wide extension
storage backend. Policy installation still involves Firefox's normal add-on
migration, so make the independent profile backup below and verify important
extension settings after the first launch. Check `about:policies` and
`about:addons` if AMO is unavailable or a policy install fails.

Two extensions require additional, machine-local integration:

- **KeePassXC-Browser** needs KeePassXC's browser integration enabled, a native
  messaging host, and a local database pairing. No database, credentials or
  pairing data are supplied here. Inspect any existing
  `~/.mozilla/native-messaging-hosts/org.keepassxc.keepassxc_browser.json`
  before changing it. We do not set `nativeMessagingHosts`: the pinned binary
  wrapper can forcibly replace files in the shared `~/.mozilla` native-host
  directory when Zen starts, potentially affecting Firefox too.
- **open in mpv** needs an `mpv://` URL handler and mpv on that machine. This
  module does not replace an existing system handler. A fresh extension install
  may prompt to run its setup on first use even if a handler exists; review the
  setup rather than running untrusted shell commands blindly. The upstream
  Linux desktop-file example interpolates the URL into shell code and should
  not be copied unchanged.

## Pinned Zen Mods

`modules/zen/mods.json` declares these ten enabled mods, in CSS cascade order:

| Mod | Version |
| --- | --- |
| Private Mode Highlighting | 1.0.5 |
| Better Active Tab | 1.1.0 |
| Pimp your PiP | 1.0.0 |
| No Gaps | 1.2.2 |
| Super Url Bar | 1.4.2 |
| Download BG | 1.0.0 |
| Remove Tab X | 1.1.1 |
| Zen Context Menu | 3.1 |
| Better Unloaded Tabs | 1.0.1 |
| Better CtrlTab Panel | 1.0.1 |

The manifest pins immutable upstream commits and SHA-256 hashes for ten
`chrome.css` files and seven `preferences.json` files. Nix fetches and verifies
them **during the build**, not during activation. Existing readmes and other
unmanaged files are not replaced; missing readmes are not provisioned. Download
BG is pinned to an archived store version matching the reported installed
hash. Remove Tab X uses its author's fixed CSS, matching the reported installed
hash, rather than the broken store CSS. For Pimp your PiP, No Gaps and Super
Url Bar, the owner approved the pinned published versions even though their CSS
hashes differ from the reported installed copies. Those three specific old
hashes are also recorded as allowed migration sources.

With Zen closed, activation merges the ten entries into the writable
`zen-themes.json`, preserves other registry entries and unknown metadata, writes
recognized pinned files as regular profile copies (preserving existing file
permissions), and regenerates `chrome/zen-themes.css` in deterministic order.
Extra enabled mods remain
active and are appended after the ten declared mods; they can therefore affect
the appearance and differ between machines. An unused folder not in the
registry (including `1e86cf37-a127-4f24-b919-d265b5ce29a0`) is ignored. A
small `nixos-dotfiles-zen-mods.json` records previously deployed hashes so a
later Nix update can recognize its own older files. Removing an entry from the
manifest does **not** delete or disable its old profile files; manage that
separately and deliberately.

**Quit Zen before every Home Manager activation**, not just the first switch.
On Linux the running browser holds a POSIX lock on `.parentlock`. Its separate
`lock -> IPv4:+PID` compatibility symlink can outlive the process or name a
different PID than the current lock holder. Preflight and reconciliation leave
the symlink untouched and accept it only while holding the lock on the existing
`.parentlock`. A symlink-only `IPv4:PID` lock (no `+`), an unrecognized marker,
or a marker without `.parentlock` still blocks activation.

If `.parentlock` is busy even after the window closes, use
`lslocks --notruncate -o PID,COMMAND,TYPE,PATH` to find the holder for this
profile. Let it exit, then retry the switch; do not delete either lock file.
A NixOS switch is not an all-or-nothing transaction and other system changes
may already have happened.

Before writing, the helper rejects invalid JSON, symlink/special-file collisions,
missing CSS for an enabled extra mod, and a managed asset whose hash is neither
pinned, one of the three approved prior hashes, nor a hash recorded by a prior
reconciliation. It will replace an existing `chrome/zen-themes.css` only when
it matches generated output for the old registry and per-mod assets (or the
empty output Zen generates with all mods disabled). Timestamp-only changes are
ignored. A generated header alone is not enough; a handwritten or modified
aggregate is a collision. Back up the file, migrate any wanted custom rules into
managed `userChrome.css` (not the generated aggregate), and move the original to
a new unused name before trying again.

The helper checks again while holding the browser's POSIX `fcntl` profile lock,
stages writes atomically per file, and attempts rollback if a write fails. A
unique backup of each replaced file and a `backup-manifest.json` are kept under
`$XDG_STATE_HOME/nixos-dotfiles/zen-mod-backups/` (normally
`~/.local/state/nixos-dotfiles/zen-mod-backups/`). The manifest lists newly
created files and records original modes; backup files themselves are private.
These backups cover **only** files replaced by this helper, not the whole
profile. Do not remove them until you have verified your independent backup
and the new setup.

`zen.mods.auto-update` is set to false. Zen 1.24.2b would still check if its
last-update timestamp were missing or its browser-version milestone changed,
so `user.js` also seeds a nonnegative last-update value and the Nix package's
version as the milestone before the mod manager starts. This suppresses that
specific automatic check when the packaged version matches Zen's reported app
version; it is not a security boundary or a guarantee for future Zen versions.
A manual update, an alternate build, or a future browser change can still
modify mods independently of Nix. If an asset changes, the next activation
stops at the hash check instead of replacing it silently. Review and repin an
intended update, or back up and move the conflicting file aside before
reapplying. Avoid the upstream `profiles.default.mods` and Sine options with
this configuration: their activation would separately mutate the same files.

## Before the first switch on **each** machine

1. Open `about:profiles`; confirm the active profile matches the table and
   inspect `~/.zen/profiles.ini`, including installation entries. If the path
   differs, stop and update that host's `custom.desktop.zen.profilePath` to the
   real existing profile rather than creating a replacement. Close **all** Zen
   processes and keep them closed until activation completes.
2. Make and verify an independent backup of the entire `~/.zen` tree. For
   example, as the desktop user:

   ```bash
   backup="$HOME/zen-before-declarative-mods-$(date +%Y%m%d-%H%M%S)"
   if [ -e "$backup" ] || [ -L "$backup" ]; then
     echo "Backup destination already exists: $backup" >&2
   elif cp -a -- "$HOME/.zen" "$backup" && diff -qr --no-dereference -- "$HOME/.zen" "$backup"; then
     echo "Backup copied and compared at $backup; verify any symlink targets separately."
   else
     echo "Backup or verification failed; stop before switching." >&2
   fi
   ```

   `cp -a` preserves symlinks, not the files they point to. Back up and verify
   any targets outside `.zen` separately. Keep an existing `~/.zen.bak`, but do
   not assume it is complete or current; Sync is not a backup. The laptop has
   no configured backup job (see [recovery](recovery.md)).

   If `profiles.ini` is a symlink (for example, to an old Home Manager
   generation), stop: Home Manager's orphan cleanup can remove it. With Zen
   closed and the full backup verified, preserve both the link and the exact
   registry bytes, then replace **only the link** with a writable regular file.
   For a link with a valid target, as the desktop user:

   ```bash
   (
     set -eu
     registry="$HOME/.zen/profiles.ini"
     test -L "$registry"
     test -f "$registry"
     saved=$(mktemp -d "$HOME/zen-registry-backup.XXXXXXXX")
     cp -a -- "$registry" "$saved/profiles.ini.link"
     cp -L -- "$registry" "$saved/profiles.ini"
     cmp -- "$registry" "$saved/profiles.ini"
     replacement=$(mktemp "$HOME/.zen/.profiles.ini.XXXXXXXX")
     trap 'rm -f -- "$replacement"' EXIT
     cat -- "$saved/profiles.ini" > "$replacement"
     cmp -- "$replacement" "$saved/profiles.ini"
     mv -T -- "$replacement" "$registry"
     printf 'Saved link and registry contents in %s\n' "$saved"
   )
   ```

   For a dangling symlink or missing registry, recover the real registry from
   a verified backup. Do not generate a new registry or discard its profile
   and install entries to bypass the guard.
3. Set `profile` to the path for **this** host and inspect possible conflicts:

   ```bash
   # Choose the right line for the current host:
   profile="$HOME/.zen/mpjpva0z.default"   # junixos
   # profile="$HOME/.zen/xtezh31k.default" # junixbook
   for target in "$profile/.keep" "$profile/user.js" "$profile/chrome/userChrome.css" "$profile/chrome/zen-themes.css"; do
     for path in "$target" "$target.backup"; do
       if [ -e "$path" ] || [ -L "$path" ]; then
         ls -ld -- "$path"
         if [ -L "$path" ]; then readlink -- "$path"; fi
       fi
     done
   done
   for name in zen-prefs-nix-managed.json zen-extension-buttons-nix-managed.json; do
     if [ -e "$profile/$name" ] || [ -L "$profile/$name" ]; then ls -ld -- "$profile/$name"; fi
   done
   ```

   The adoption guard stops before Home Manager links if `.keep`, `user.js`,
   or managed userChrome/userContent is an unmanaged file or foreign symlink,
   including a dangling link; it accepts links from prior Home Manager
   generations. After the independent backup, inspect any collision, migrate
   wanted preferences/CSS into Nix, and move the original to a **new unused**
   name. Do not overwrite an existing backup or use `force`. The helper also
   stops if either upstream cleanup marker above exists: those upstream
   fragments could otherwise edit `prefs.js`. Inspect and back up the marker
   and prefs, and only move the marker aside after deciding how to preserve its
   old settings.
4. Build without activation, then switch with Zen still closed. Use the host
   name for the machine you are on:

   ```bash
   host=junixos  # Set to junixbook on the laptop.
   nix build .#checks.x86_64-linux.zen-options
   nix build ".#nixosConfigurations.${host}.config.system.build.toplevel" --no-link
   sudo nixos-rebuild switch --flake ".#${host}"
   systemctl status home-manager-julian.service
   ```

   Git flakes need new files staged or committed before evaluation. A build or
   dry run cannot fully predict activation-time profile collisions. If a guard
   reports an unexpected mod hash (particularly on the laptop, whose installed
   mod hashes were not supplied), inspect that file locally and compare it with
   the pinned source. After backing it up, explicitly approve a known old hash
   in the manifest or move the file to a new unused name; never discard it just
   to bypass the guard. Then retry. If the helper cannot verify a legacy `lock`,
   inspect the profile on every machine that can use it rather than assuming the
   recorded PID is stale. The fcntl lock covers reconciliation, not the entire
   Home Manager activation, so do not reopen Zen during the switch.
5. If activation fails, read `journalctl -u home-manager-julian.service -b`.
   The helper reports its backup directory and attempts to roll back completed
   writes, but a crash or failed rollback can leave a partial update. Keep Zen
   closed, inspect the backup manifest and current files, and restore from a
   verified backup deliberately; do not overwrite newer data blindly. After a
   successful switch, start Zen, verify `about:profiles`, mods, extensions,
   tabs, Sync and KeePassXC/mpv integrations.
