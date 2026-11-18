# Zen Browser and existing profiles

Zen is installed through Home Manager when `custom.desktop.browsers.enable` is
on. Its package and policies are declarative; app updates and telemetry are
disabled by default, so update Zen by updating the flake input. A Home Manager
override of `programs.zen-browser.enable` can change the default independently.

## What is managed on `junixos`

`hosts/junixos/home.nix` adopts the reported existing profile at
`~/.zen/mpjpva0z.default`. The Zen wrapper is configured to use `~/.zen` as its
application data directory. Home Manager manages only these profile files:

- `mpjpva0z.default/.keep`, an empty directory marker;
- `mpjpva0z.default/user.js`, currently declaring
  `browser.aboutConfig.showWarning = false`. This preference is reapplied on
  browser startup; change it in Nix if you want a different value.

The existing `~/.zen/profiles.ini` is **not** managed by Home Manager. It stays
writable and retains its other profiles and installation entries. Consequently,
`id` and `isDefault` in the Nix profile declaration do not change which profile
Zen actually selects; the existing registry and Zen's installation selection
remain authoritative. The wrapper also sets `MOZ_LEGACY_PROFILES=1`.

No extensions, bookmarks, search engines, handlers, pins or spaces are declared
here. Existing profile databases, sessions and Sync-managed extensions are not
replaced by these declarations. Firefox Sync is not a complete local backup.
Nix-generated `user.js` is in the world-readable Nix store: do not put secrets
in profile settings.

The pinned upstream Zen module includes activation cleanup for previously
Nix-managed preset preferences and extension buttons. With no corresponding
old state files it does nothing. If the profile contains
`zen-prefs-nix-managed.json` or `zen-extension-buttons-nix-managed.json`, the
cleanup can edit `prefs.js` and remove/update those markers, so inspect and
back up the profile first. Close Zen before activation; the upstream cleanup
skips its changes if the profile is in use.

## Before the first `junixos` switch

1. In Zen, open `about:profiles` and confirm that the profile actually in use
   has root directory `~/.zen/mpjpva0z.default`. Inspect `~/.zen/profiles.ini`,
   including its installation entries, and confirm they still point to the
   intended profile. If not, update the host declaration to the **existing**
   path and stop; do not create an empty replacement profile. Close all Zen
   processes before backing up or switching.
2. Make and verify an independent backup of the whole profile tree. For example,
   as the desktop user:

   ```bash
   backup="$HOME/zen-before-home-manager-$(date +%Y%m%d-%H%M%S)"
   if [ -e "$backup" ] || [ -L "$backup" ]; then
     echo "Backup destination already exists: $backup" >&2
   else
     cp -a -- "$HOME/.zen" "$backup"
     echo "Backup created at $backup; verify it before proceeding."
   fi
   ```

   `cp -a` preserves symlinks rather than copying their targets. If `.zen` or
   the profile contains symlinks to data elsewhere, back up and verify those
   targets separately. Keep any existing `.zen.bak` as well.
3. Inspect the targets and possible Home Manager backups without changing them:

   ```bash
   profile="$HOME/.zen/mpjpva0z.default"
   for target in "$profile/user.js" "$profile/.keep"; do
     for path in "$target" "$target.backup"; do
       if [ -e "$path" ] || [ -L "$path" ]; then
         ls -ld -- "$path"
         if [ -L "$path" ]; then readlink -- "$path"; fi
       fi
     done
   done
   for name in zen-prefs-nix-managed.json zen-extension-buttons-nix-managed.json; do
     if [ -e "$profile/$name" ]; then ls -l -- "$profile/$name"; fi
   done
   ```

4. The adoption guard deliberately **stops activation** if `profiles.ini` or
   the profile directory is missing, or if the generated `user.js` would replace
   an unmanaged regular file or foreign symlink (including a dangling link).
   It allows `user.js` links from existing Home Manager generations. If the
   guard reports an unmanaged `user.js`, inspect its contents, migrate the
   preferences you want into `programs.zen-browser.profiles.default.settings`
   or `extraConfig`, and move the old file or link to a **new, unused** name
   after backing up its target. Do not overwrite an existing backup. The guard
   checks existence, not whether the registry selects the right profile; step 1
   remains necessary.

   The guard does not cover `.keep` or other Home Manager files. The shared
   `home-manager.backupFileExtension = "backup"` may move a conflicting regular
   file to `<name>.backup`; activation fails if that backup already exists and
   would be overwritten. Foreign symlinks are not automatically backed up and
   may cause a collision or be replaced (especially dangling links). Inspect
   and safely move any conflicting links/files aside first. Do not use `force`
   or remove `profiles.ini` to bypass a collision.
5. After staging new files (Git flakes only include tracked files), build
   without activating, then switch only after the checks above:

   ```bash
   nix build .#nixosConfigurations.junixos.config.system.build.toplevel --no-link
   sudo nixos-rebuild switch --flake .#junixos
   systemctl status home-manager-julian.service
   ```

   A build/dry-run cannot inspect activation-time collisions. If activation
   fails, check `journalctl -u home-manager-julian.service -b`, resolve the
   reported conflict and retry. Then start Zen, confirm the active profile in
   `about:profiles`, and check your tabs and Sync state.

## Adopting a profile on another host

`junixbook` installs Zen through Home Manager but deliberately declares no
profile and no application-data override: its existing local path has not been
verified. It retains the browser's normal profile selection. Sync does not imply
that its directory name or location matches `junixos`.

On the laptop, first use `about:profiles` and its local `profiles.ini` to find
its actual configuration directory and active profile. Back them up and inspect
collisions as above. Then, in `hosts/junixbook/home.nix`, declare that existing
relative directory in `programs.zen-browser.configPath` and
`programs.zen-browser.profiles.default.path`, leave the corresponding
`home.file."${config.programs.zen-browser.configPath}/profiles.ini".enable`
false if the registry has entries to preserve, and opt into the same safety
guard:

```nix
home.activation.checkExistingZenProfile = import ../../lib/zen-profile-guard.nix {
  inherit config lib pkgs;
  profileName = "default";
};
```

Add `config`, `lib` and `pkgs` to the host module's arguments. Check the actual
registry/profile selection manually and migrate any existing `user.js` before
activation. Do not copy the desktop's profile directory name or blindly replace
`profiles.ini` just because the browsers use the same Sync account.
