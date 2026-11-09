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

## Reinstalling junixsrv

`junixsrv` runs as a `systemd-nspawn` container on a Debian 12 host under
`/var/lib/machines/junixsrv`.

1. On the Debian 12 host, install the container tooling:
   `sudo apt install systemd-container`
   (If replacing an existing rootfs, clear NixOS's immutable flag before
   removing the old tree: `sudo chattr -i /var/lib/machines/junixsrv/var/empty`.)
2. On an existing NixOS machine, pre-generate or restore the container's SSH
   host key (`ssh-keygen -t ed25519 -N "" -f ssh_host_ed25519_key`), add its
   `ssh-to-age < ssh_host_ed25519_key.pub` recipient as `&host_junixsrv` in
   `.sops.yaml` (include `*host_junixsrv` under `secrets/common\.yaml$` and add
   a `secrets/junixsrv\.yaml$` rule **above** the catch-all
   `secrets/[^/]+\.yaml$` rule), run `sops updatekeys secrets/common.yaml` **and**
   `sops updatekeys secrets/junixsrv.yaml`, then provision two repository-scoped
   GitHub deploy keys in `secrets/junixsrv.yaml`
   (GitHub forbids reusing one deploy key across two repositories):
   - `nix_nightly_ssh_key`: read/write deploy key on `Irgendeinwer/NixOS-Dotfiles`
   - `wallpaper_deploy_key`: read-only deploy key on `Irgendeinwer/wallpaper`
   The dedicated deploy keys mean the nightly job does not need to install the
   personal `user_ssh_key` for its own Git operations. However, `junixsrv` is
   currently a recipient of `secrets/common.yaml`, so its root can decrypt every
   secret in that file, including `user_ssh_key`. Before relying on that boundary,
   move `user_ssh_key` to `secrets/users/julian.yaml` with SOPS and re-encrypt
   `secrets/common.yaml`; the user-specific recipient rule excludes `junixsrv`,
   and the remote-builder module prefers that file when present. Because earlier
   ciphertext remains in Git history, rotate the SSH key and update the server's
   authorized key list as well.
   The `junixsrv` configuration enables Discord notifications, so ensure the
   `nix_nightly_webhook` key described below is present before deploying it.
3. Build the rootfs archive and copy it to the Debian host:
   `nix build .#nixosConfigurations.junixsrv.config.system.build.tarball`
4. Extract `result/tarball/nixos-container-junixsrv-x86_64-linux.tar.xz`
   into `/var/lib/machines/junixsrv` with `sudo tar --numeric-owner -xpf`,
   and install `ssh_host_ed25519_key` (`0600`) and `ssh_host_ed25519_key.pub`
   (`0644`) into `/var/lib/machines/junixsrv/etc/ssh/` so secrets decrypt
   cleanly on first boot.
5. Write `/etc/systemd/nspawn/junixsrv.nspawn` and the cgroup v2 unit drop-in
   before first start (`PrivateUsers=no` keeps `/nix/store` ownership intact
   and shares UID 0 trust with the host; `SystemCallFilter=@pkey @keyring` adds
   `@pkey` and `@keyring` to nspawn's seccomp allowlist for Nix build sandboxes;
   `SYSTEMD_NSPAWN_UNIFIED_HIERARCHY=1` prevents Debian 12's `nspawn` v252 from
   falling back to legacy cgroup v1 when FHS `/lib/systemd` is absent):
   ```ini
   # /etc/systemd/nspawn/junixsrv.nspawn
   [Exec]
   Boot=yes
   PrivateUsers=no
   Capability=CAP_SYS_ADMIN CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_SETPCAP
   SystemCallFilter=@pkey @keyring
   ResolvConf=off
   Timezone=off

   [Network]
   VirtualEthernet=no
   MACVLAN=<wired-interface>
   ```
   ```ini
   # /etc/systemd/system/systemd-nspawn@junixsrv.service.d/override.conf
   [Service]
   Environment=SYSTEMD_NSPAWN_UNIFIED_HIERARCHY=1
   CPUQuota=960%
   MemoryHigh=10G
   MemoryMax=12G
   MemorySwapMax=1G
   ```
   `MACVLAN=` requires a wired Ethernet interface (802.11 Wi-Fi APs reject
   secondary MACs) and isolates direct IP traffic between the Debian host
   itself and `junixsrv` unless a host-side macvlan shim is configured. Use
   `sudo machinectl shell junixsrv` from the Debian host, or SSH to
   `junixsrv.local` from another LAN machine.
6. Run `sudo systemctl daemon-reload`, then enable and start the container with
   `sudo machinectl enable junixsrv && sudo machinectl start junixsrv`.
   If `/etc/ssh` or `/var/lib/harmonia` was not restored from a previous
   backup, update `hostPublicKey` and `cachePublicKey` in
   `modules/nixos/remote-builder.nix` with the new keys from
   `/etc/ssh/ssh_host_ed25519_key.pub` and `/var/lib/harmonia/cache-pub-key.pem`,
   then deploy updates from a LAN client with:
   `nh os switch ~/dotfiles -H junixsrv --target-host root@junixsrv.local`

The default Lix configuration keeps its normal namespace probing and
socket-activated `nix-daemon@` instances; builds normally use `/nix/var/nix/b`.
The legacy `without-userns` wrapper applies only when selecting C++ Nix
(`custom.system.lix.enable = false`). It is a compatibility workaround, not a
user-namespace security boundary: `clone3` is disabled as a whole and
`setns(fd, 0)` cannot distinguish an existing user namespace from a network
namespace. Lix's packaged pasta path is explicitly disabled in this container
because `/dev/net/tun` is not exposed.

Keys in `custom.services.buildServer.authorizedKeys` authenticate the trusted
Nix user `nixbuilder`. Treat these as root-equivalent keys, even if adding SSH
command restrictions: ordinary input-addressed `ssh-ng` builds need daemon
trust, not merely permission to upload unsigned store paths. With
`PrivateUsers=no`, the container is also not a strong boundary from the host.

## Nightly notifications

`junixsrv` reports the result of every `nix-nightly-update` run directly to
Discord (`custom.services.buildServer.nightly.notify.enable = true`). This
notification option is off by default on other hosts.

- no updates: nixpkgs is already current; pre-build and self-upgrade still run
- success: updated inputs were built and published
- warning: activation was deferred because the updated `flake.lock` could not be
  pushed or `main` advanced during the run. Staged roots are removed when
  publication fails, so unpublished outputs may be garbage-collected. If `main`
  advances after root promotion but before activation, tested closures remain
  cached while activation is deferred; cache publication and the running
  generation need not match.
- failure: stage and exit code; the full log remains on the host at
  `/var/lib/nix-nightly/last-run.log` (root-only, mode `0600`)

Delivery is best-effort and never changes the nightly run's exit status. The
service attempts a failure notification after its four-hour startup timeout,
but systemd may still kill the unit before delivery completes. Raw logs are
never sent to Discord or copied into the journal; log setup does not change
activation's umask. Curl errors and response bodies are suppressed because they
can echo webhook credentials; delivery warnings include only a numeric exit
status. Summaries contain run metadata such as host names, lock and push status,
duration, and upgrade state. Restrict access to the channel.
The webhook sends the display name `Nix Nightly` and a public `avatar_url` for
`assets/nightly-icon.png`, rendered from `assets/icon.svg`. Discord fetches the
PNG from this repository's `main` branch, so it appears after the asset is
published there. A failed pre-build is still reported as a failure even if no
nixpkgs update was available.

1. Create the webhook in Discord: *Server Settings → Integrations → Webhooks →
   New Webhook*, then copy its URL.
2. Store it as `nix_nightly_webhook` in the host secrets file — the URL is a
   credential, so it must not be committed in plaintext:
   `sops secrets/junixsrv.yaml`
   ```yaml
   nix_nightly_webhook: https://discord.com/api/webhooks/<id>/<token>
   ```
3. Deploy (`nh os switch -H junixsrv --target-host root@junixsrv.local`); the
   secret is installed at `/run/secrets/nix_nightly_webhook` (`0400`, root) and
   read at runtime.
4. Smoke-test the webhook without triggering a full run:
   ```bash
   url="$(sudo cat /run/secrets/nix_nightly_webhook)"
   if ! jq -n '{username:"Nix Nightly",embeds:[{title:"test",description:"junixsrv nightly hook"}]}' \
     | curl --config <(printf 'url = "%s"\n' "$url") --globoff --proto '=https' \
         --silent --fail --max-time 8 -H 'Content-Type: application/json' \
         --data-binary @- >/dev/null 2>&1; then
     echo 'Webhook smoke test failed; raw diagnostics suppressed to protect the URL.' >&2
   fi
   unset url
   ```
   The first real report then arrives after the next 02:15 run. A switch that
   precedes step 2 fails in `sops-install-secrets` because the key does not
   exist yet.

GC-root promotion replaces host links individually, not as a single transaction.
If a run is interrupted, the cache can temporarily retain a mixture of old and
new closures; a later successful run rebuilds and replaces them. Staging data
from older versions that contains a rollback transaction is retained under
`/nix/var/nix/gcroots/nix-nightly/.staging.*` and reported in the nightly log;
inspect it before removing it after a successful run.
