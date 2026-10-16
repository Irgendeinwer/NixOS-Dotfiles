# Recovery and reinstall

What matters when a disk or a whole machine is lost, what the backup
covers, and how to reinstall junixbook on a new disk.

## The keys that matter

- **User age key** (`~/.config/sops/age/keys.txt`): decrypts every file
  in `secrets/`, because `user_julian` is a recipient of all of them
  (see `.sops.yaml`). Losing it means recreating all secrets, including
  the borg passphrase. Keep a copy off the machines, mode `600`.
- **Host SSH keys** (`/etc/ssh`): each host decrypts sops with the age
  key derived from its SSH host key. Restoring them is convenient, not
  required; new keys work after the rekey steps below.
- **Secure Boot keys** (`/var/lib/sbctl`): restoring them skips creating
  new ones. Enrolling them into the firmware is per machine and must be
  redone on new hardware either way.
- **Syncthing identity** (`cert.pem` and `key.pem` in
  `~/.config/syncthing`): the device IDs are pinned in
  `modules/services/syncthing.nix`. Restoring these files keeps the
  pairing; losing them means a new device ID, a module update and
  re-approving the device on the others.
- **`~/.ssh/id_ed25519`** needs no backup: sops materializes it from
  `secrets/`, and with it the SSH access to the private repositories.

## What the backup covers

The borg job runs on junixos only (external disk, daily and on plug-in)
and covers the home directory, `/media/fun` (music, audiobooks,
gallery), `/etc/ssh`, `/var/lib/sops-nix` and `/var/lib/sbctl`.

Not covered:

- **junixbook has no backup job.** Its age key, `/etc/ssh` and Syncthing
  identity exist only on the laptop; copy them somewhere safe by hand.
- Service state under `/var/lib` (Immich and Jellyfin databases). Their
  media files are covered, the databases are not.
- The Nix store and everything else reproducible from this flake.

## Reinstalling junixbook

The target layout (LUKS, btrfs, same subvolumes as junixos) is prepared
in `hosts/junixbook/disk-config.nix`.

1. Boot the NixOS installer and clone this repo. Evaluating the flake
   needs SSH access to the private wallpaper input, so have the user
   SSH key available (or a checkout copied from another machine).
2. In `hosts/junixbook/disk-config.nix`, replace the placeholder device
   with the new disk (`ls /dev/disk/by-id`).
3. In `flake.nix`, add `inputs.disko.nixosModules.disko` and
   `./hosts/junixbook/disk-config.nix` to the junixbook module list,
   mirroring the junixos entries.
4. Format and mount (asks for the LUKS passphrase, this destroys the
   target disk's contents):
   `sudo nix run github:nix-community/disko -- --mode destroy,format,mount --flake .#junixbook`
5. Run `nixos-generate-config --root /mnt`. Take its
   `hardware-configuration.nix`, delete the `fileSystems` and
   `swapDevices` entries (disko owns them now) and replace
   `hosts/junixbook/hardware-configuration.nix` with the result.
6. Install: `sudo nixos-install --flake .#junixbook`. Set the root
   password when asked; it is the lifeline until sops works.
7. Rekey sops for the new host key. Boot, log in as root, get the age
   public key with `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`,
   put it in `.sops.yaml` (the `host_junixbook` anchor), then run
   `sops updatekeys secrets/common.yaml` on a machine holding the user
   age key. Commit, push, pull on the laptop, rebuild. Also place the
   user age key at `~/.config/sops/age/keys.txt` (mode `600`) so Home
   Manager secrets work.
8. Secure Boot: restore `/var/lib/sbctl` or run `sbctl create-keys`,
   put the firmware into setup mode, `sbctl enroll-keys --microsoft`,
   rebuild, reboot, enable Secure Boot and check with `sbctl verify`.
9. Syncthing: restore `cert.pem` and `key.pem`, or accept the new
   device ID, update `modules/services/syncthing.nix` and re-approve
   the device on the other machines.

The same rekey and enrollment steps apply when replacing either
machine: add the new host key to `.sops.yaml`, run `sops updatekeys`
on the affected files, and remove the old host anchor once the machine
is gone for good.
