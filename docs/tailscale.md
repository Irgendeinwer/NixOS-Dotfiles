# Private access to junixsrv

`junixsrv` and `junixbook` run Tailscale via `custom.services.tailscale`;
`junixos` stays off the tailnet. Approved clients can reach `junixsrv` without
a WAN port forward, both from outside the LAN and when connected to the same
LAN as the server.

## How LAN and remote access coexist

- **No subnet routing, exit node, or DNS takeover:** `useRoutingFeatures` stays
  `"none"` and `acceptDns` defaults to `false`. Tailscale adds routes only for
  tailnet peer addresses in table `52`, so local RFC 1918 LAN traffic, Avahi
  mDNS (`junixsrv.local`), captive portals, and school/corporate networks work
  unchanged.
- **Direct LAN WireGuard (`UDP 41641`):** `custom.services.tailscale.openFirewall`
  defaults to `true`, opening only the encrypted WireGuard/Disco UDP port
  (`41641`) while keeping `tailscale0` **out** of
  `networking.firewall.trustedInterfaces`. On `junixsrv`, `tailscaled` is
  configured to use native `nf_tables` netlink (`TS_DEBUG_FIREWALL_MODE=nftables`)
  and `systemd-networkd` preserves Tailscale's policy routing rules across
  reloads. When `junixbook` is on the same LAN as `junixsrv`, connections to
  `junixsrv`'s Tailscale address establish a direct local WireGuard path
  (`via <lan-ip>:41641`, sub-millisecond RTT, no WAN hairpin or DERP relay) and
  keep active SSH or streaming TCP sessions alive when roaming onto a hotspot.
- **Path MTU sizing (`mtu = 1180`):** Direct peer-to-peer WireGuard over reduced
  IPv6/DS-Lite/hotspot underlays adds 80 bytes of outer IPv6 + UDP + WireGuard
  framing and can blackhole packets at Tailscale's default `1280` TUN MTU. Both
  `junixbook` and `junixsrv` set `custom.services.tailscale.mtu = 1180`
  (`TS_DEBUG_MTU=1180`), clamping both TCP and UDP/QUIC (`udp:22000` Syncthing)
  payloads in both directions. Setting MTU below `1280` disables Tailscale's
  internal `fd7a::` overlay IPv6 on `tailscale0` while leaving the outer ISP
  IPv6 underlay untouched.
- **Raw LAN priority for Nix builds and cache:** `custom.system.remoteBuilder`
  keeps `junixsrv.local` for automatic distributed builds and Priority `30`
  LAN binary substitutions, avoiding WireGuard overhead at home and avoiding
  residential-uplink bottlenecks when remote.

## Verify container TUN support

`junixsrv` runs inside `systemd-nspawn` on Debian 12 with `MACVLAN=`, which
already provides a private network namespace with `CAP_NET_ADMIN` and
`CAP_NET_RAW`. Stock Debian 12 `systemd-nspawn@.service` also declares
`Wants=modprobe@tun.service` and `DeviceAllow=/dev/net/tun rwm`, so
`/dev/net/tun` is normally present inside `junixsrv` without host overrides.

Verify inside the running container before deploying:

```sh
ssh root@junixsrv.local 'test -c /dev/net/tun && echo ok'
```

Only if `/dev/net/tun` is missing (for example on a custom host kernel without
`tun` loaded when the container started), load it on the **Debian host** and
restart the guest during a maintenance window:

```sh
sudo modprobe tun
printf 'tun\n' | sudo tee /etc/modules-load.d/junixsrv-tun.conf
sudo systemctl restart systemd-nspawn@junixsrv.service
```

## Restrict access in the tailnet

In the Tailscale admin console, merge the following `tagOwners` and `grants`
into your tailnet policy and remove or narrow any default allow-all rule
(grants are additive):

```json
{
  "tagOwners": {
    "tag:junixsrv": ["autogroup:admin"],
    "tag:junixsrv-client": ["autogroup:admin"]
  },
  "grants": [
    {
      "src": ["tag:junixsrv-client"],
      "dst": ["tag:junixsrv"],
      "ip": [
        "icmp:*",
        "tcp:22",
        "tcp:80",
        "tcp:443",
        "tcp:5000",
        "tcp:4533",
        "tcp:22000",
        "udp:22000"
      ]
    }
  ]
}
```

- `icmp:*`: IP-layer ping and Path MTU Discovery diagnostics.
- `tcp:22`, `tcp:80`, `tcp:443`, `tcp:5000`: OpenSSH, HTTPS overview portal
  (plus `:80` redirect), and Harmonia binary cache.
- `tcp:4533`, `tcp:22000`, `udp:22000`: Navidrome and Syncthing (TCP + QUIC)
  on `junixsrv`.

Apply `tag:junixsrv` only to `junixsrv` and `tag:junixsrv-client` only to
approved clients (`junixbook`). Tagging an existing device changes its ACL
identity to the tag **without** altering its current key-expiry state, whereas
authenticating with a tag disables key expiry by default:

- On `junixsrv`: disable key expiry for unattended server operation.
- On `junixbook`: keep key expiry enabled (and re-check it after any
  re-authentication while tagged); remove lost or retired devices from the
  admin console.

OpenSSH still requires an authorized public key. Note that
`custom.system.container.authorizedKeys` currently authorizes `irgendeinwer`, `root`,
and the trusted `nixbuilder` daemon account on `junixsrv`.

## Enroll the nodes

1. Deploy `junixsrv` over the LAN (`nh os switch ~/dotfiles -H junixsrv --target-host root@junixsrv.local`)
   and switch `junixbook` (`sudo nixos-rebuild switch --flake .#junixbook`).
2. Authenticate both nodes interactively (no auth key is stored in this repo):
   - On `junixsrv`: `sudo tailscale up --accept-dns=false --shields-up=false`
   - On `junixbook`: `sudo tailscale up --accept-dns=false --shields-up=true`
   (`tailscaled-set.service` also reconciles these flags declaratively on boot
   and on future `nixos-rebuild switch` runs.)
3. Assign `tag:junixsrv` and `tag:junixsrv-client` in the admin console,
   verify key expiry on both nodes, and confirm `junixsrv`'s IPv4 address from
   `tailscale ip -4` matches `hosts/junixbook/configuration.nix`
   (`100.110.103.47`):
   ```nix
   custom.services.tailscale = {
     enable = true;
     mtu = 1180;
     peers."junixsrv.internal" = "100.110.103.47";
   };

   custom.system.remoteBuilder = {
     enable = true;
     maxJobs = 3;
     tailscaleHost = "junixsrv.internal";
     tailscaleSubstituter = true;
   };
   ```
   With `tailscaleHost` set, `programs.ssh.knownHosts` automatically pins
   `junixsrv`'s Ed25519 host key for `junixsrv.local`, `junixsrv.internal`, and
   `100.110.103.47` so remote `ssh` and `nh os switch` verify the server key
   without an interactive TOFU prompt.

For any future NixOS client, set `custom.services.tailscale.enable = true;`
(`shieldsUp = true` and `acceptDns = false` are the module defaults).

## Service behavior across LAN and remote networks

### SSH and remote deployments

Once `peers` and `tailscaleHost` are set, `ssh irgendeinwer@junixsrv.internal` and
`nh os switch ~/dotfiles -H junixsrv --target-host root@junixsrv.internal` work
both remotely and on the home LAN. Active SSH/`tmux` sessions to
`junixsrv.internal` survive switching between home Wi-Fi and a mobile hotspot;
`junixsrv.local` remains available on the LAN even if Tailscale is stopped.

### Harmonia and build server behavior

Harmonia on `junixsrv` advertises `Priority: 30`, which is higher priority than
`https://cache.nixos.org` (`Priority: 40`). On Gigabit LAN (`junixsrv.local`),
that is ideal; over a remote connection, using Priority `30` would pull
standard `nixpkgs` closures through `junixsrv`'s residential upload link
instead of Fastly's CDN.

`custom.system.remoteBuilder` avoids that slowdown in two ways:

1. **Automatic `nix.buildMachines` stays on `junixsrv.local`:** On the LAN,
   builds offload automatically and `http://junixsrv.local:5000` serves
   substitutions at Priority `30`. Away from the LAN, `remote-builder-mdns`
   removes `junixsrv.local` from `/etc/hosts`, so Nix immediately falls back to
   `cache.nixos.org` (Priority `40`) and local builds.
2. **Optional low-priority remote cache (`tailscaleSubstituter = true`):**
   Appends `http://<tailscaleHost>:5000?priority=50`. On the LAN, Priority `30`
   (`junixsrv.local`) still wins. When remote, `cache.nixos.org` (Priority `40`)
   serves all upstream packages at CDN speed, and `junixsrv` (Priority `50`) is
   queried **only** for custom derivations missing from `cache.nixos.org` (such
   as the patched `feishin` build pre-built overnight). Leave
   `tailscaleSubstituter = false` if you frequently run `tailscale down`, as
   unreachable RFC 6598 addresses wait for `nix.settings.connect-timeout` (3s).

To offload a heavy build remotely on demand without enabling automatic remote
offload:

```sh
sudo nix build .#nixosConfigurations.junixbook.config.system.build.toplevel \
  --builders 'ssh-ng://nixbuilder@junixsrv.internal x86_64-linux - 3 2 big-parallel,benchmark'
```

### Navidrome and Syncthing

- **Syncthing (`tcp:22000`, `udp:22000`):** `junixsrv` (`QAMX456-...`) shares
  `Documents`, `Schule-26-27`, `Music`, and `E-Books`; `junixbook` omits `Music`
  and streams from Navidrome on `junixsrv` instead.
  1. Deploy the updated configuration on `junixsrv`, `junixos`, and `junixbook`,
     and add/approve `junixsrv` on `MobileF6`.
  2. On `junixbook`, `syncthing-init` automatically unshares `Music` (`#Noice`
     is also removed everywhere). Only **after** switching `junixbook` should
     you delete `/home/irgendeinwer/music` on the laptop if reclaiming disk space, so
     deletions are never propagated to `junixos`, `junixsrv`, or `MobileF6`.
  3. Because `custom.system.remoteBuilder.tailscaleHost` is set to
     `junixsrv.internal` on `junixbook`, Syncthing automatically dials
     `junixsrv.local:22000` on the LAN and `junixsrv.internal:22000` over
     Tailscale when remote, without public relays. The web GUI stays local
     (`127.0.0.1:8384`); forward it on demand with
     `ssh -L 8384:127.0.0.1:8384 irgendeinwer@junixsrv.internal`.
- **Navidrome (`tcp:4533`):** `junixsrv` serves `/home/irgendeinwer/music` via
  `custom.services.navidrome` while `junixos` keeps Jellyfin for movies. Open
  `http://junixsrv.local:4533` once on the LAN to create the Navidrome admin
  account, then point Feishin to `http://junixsrv.local:4533` on `junixos` and
  `http://junixsrv.internal:4533` (or `junixsrv`'s Tailscale IP) on `junixbook`
  so the laptop uses direct LAN WireGuard at home and roams seamlessly away
  from home.

## Verify on the same LAN and from outside

1. **On the same LAN as `junixsrv`:**
   ```sh
   server_ts='junixsrv.internal'
   tailscale status
   tailscale ping -c 3 "$server_ts"
   ssh "irgendeinwer@$server_ts" true
   ssh irgendeinwer@junixsrv.local true
   curl --fail "http://junixsrv.local:5000/nix-cache-info"
   curl --fail "http://$server_ts:5000/nix-cache-info"
   ```
   `tailscale ping` on the LAN should report a direct local endpoint
   (`via <junixsrv-lan-ip>:41641`) rather than `via DERP(...)`.
2. **Outside the LAN (for example on a phone hotspot):**
   ```sh
   server_ts='junixsrv.internal'
   ip -d link show dev tailscale0 | grep 'mtu 1180'
   tailscale ping --until-direct=false -c 5 "$server_ts"
   ping -c 3 -M do -s 1152 "$server_ts"
   ssh "irgendeinwer@$server_ts"
   curl --fail "http://$server_ts:5000/nix-cache-info"
   curl --fail -I "http://$server_ts:4533/app/"
   curl --fail -I "https://$server_ts/"
   ```
   The first reply may use `via DERP(...)` before NAT traversal establishes a
   direct path (`via <ip>:<port>`).
