# Custom options and module scopes

The tables below inventory this repository's `custom.*` options. Names in a
row share the indicated prefix. Check the source module for full descriptions,
assertions and current defaults. These are repository options, not a general
NixOS module collection: the shared baseline also applies to every host.

Most `enable` options default to `false`. Exceptions are explicitly noted below.
A dotted name is a namespace, **not** an implicit dependency: for example,
`gaming.isolated.enable`, `gaming.arkServer.enable`,
`gaming.factorioServer.enable`, and `hardware.amdgpu.lact.enable` work without
their similarly named parent features. Where one flag actually gates another,
the table says so.

## NixOS scope

Set these in a host's `configuration.nix`. The primary user defaults to
`custom.user = "julian"`; feature-specific `user` options generally default
to that value.

| Prefix | Options and behavior |
| --- | --- |
| `custom.system` | `android.enable`, `android.user`; `direnv.enable`, `lix.enable`, `nh.enable` (all three default **true**); `kernel` (`latest` by default, `lts` or `cachyos`; ignored for containers). |
| `custom.system.boot` | `silent.enable`; `secureboot.enable`, `secureboot.pkiBundle`. |
| `custom.system.container` | `enable`, `authorizedKeys`; sets up the nspawn baseline and the container's SSH keys. |
| `custom.system.power` | `upower.enable`, `ignorePowerKey`, `suspendThenHibernate.enable`, `suspendThenHibernate.hibernateDelaySec` (unsigned seconds, default 3600). These power features are independently selected. |
| `custom.system.remoteBuilder` | `enable`, `offload` (default true), `host`, `hostPublicKey`, `cachePublicKey`, `maxJobs` (positive). Offload, the client key and remote builds take effect only when the feature is enabled; cache-only operation is supported. |
| `custom.system.security.hardening` | `enable`, `lockdownEmergencyShell` (default false). Emergency-shell lockdown is applied only with hardening enabled. |
| `custom.desktop` | `enable`, `wayland.enable`, `fonts.enable`; their related defaults and independent overrides are described below. |
| `custom.desktop.hyprland` | `enable`, `layerBlur`, `monitors`. The last two affect the Hyprland session only. |
| `custom.desktop.greetd` | `enable`, `command`, `initialSessionCommand`, `user`. `command` defaults to `start-hyprland`; choose a different command explicitly for another session. With Hyprland and that default command, the boot auto-login defaults to starting locked. |
| `custom.desktop.getty` | `enable`, `user`. `getty.enable` and `greetd.enable` cannot both be true. |
| `custom.desktop.gaming` | `enable`, `user` install native gaming tools; `isolated.enable` independently enables Flatpak gaming; `arkServer.enable`/`user` and `factorioServer.enable`/`user` independently enable their on-demand servers. The existing ARK configuration is intentionally unchanged. |
| `custom.desktop.media` | `enable`, `royalPresetProfile` (`calm`, `balanced`, `intense`; default `balanced`). The system value also selects the Home Manager visualizer preset. |
| `custom.desktop` | Independent package/feature toggles: `browsers.enable`, `flexing.enable`, `messaging.enable`, `obs.enable`, `office.enable`, `sound.enable`, `tools.enable`, `vscode.enable`. Browser selection installs Zen via Home Manager and the other browsers system-wide. |
| `custom.hardware.amdgpu` | `enable` for OpenCL; `lact.enable` independently enables the LACT daemon. |
| `custom.hardware` | `bluetooth.enable`; `xbox-controller.enable`, `xbox-controller.disableLed`. The LED rule is applied only while the controller feature is enabled. |
| `custom.services.ai` | `enable`, `user`, `secretsFile`, `geminiKeyCount` (positive, default 10). |
| `custom.services.backup` | `enable`, `mountPoint`, `deviceUuid`, `repoName`, `startAt`, `autoTriggerOnPlug`. An enabled backup requires `deviceUuid`. |
| `custom.services.buildServer` | `enable`, `openFirewall`, `authorizedKeys`, `nightly.enable` (default true), `nightly.dates`, `nightly.hosts`, `nightly.notify.enable` (default false). Nightly and notification settings take effect only when the build server and, for notifications, nightly updates are enabled. Authorized build keys grant highly privileged access. |
| `custom.services.hotspot` | `enable`, `wifiInterface`, `ethernetInterface`, `ssid`, `password`, `passwordFile`. An enabled hotspot needs both interfaces and a password or password file; prefer a sops-backed `passwordFile`. |
| `custom.services.immich` | `enable`, `openFirewall`, `host`, `mediaLocation`. |
| `custom.services.jellyfin` | `enable`, `openFirewall`. |
| `custom.services.syncthing` | `enable`, `user`, `openFirewall`. |
| `custom.services.archisteamfarm` | `enable`, `webUi`. |
| `custom.services` | Independent toggles: `meilisearch.enable`, `openrgb.enable`, `playerctl.enable`, `printing.enable`, `zapret.enable`. |
| `custom.theme` | `palette`, shared with system console, Nixvim and Home Manager by default. See [Palette](#palette). |

### Desktop and Wayland defaults

- `custom.desktop.wayland.enable` defaults to `custom.desktop.hyprland.enable`.
- `custom.desktop.enable` defaults to `custom.desktop.wayland.enable`.
- `custom.desktop.fonts.enable` defaults to `custom.desktop.enable`.

These are defaults, not forced parent dependencies. Explicit settings override
them independently. For example, an X11 session can set
`custom.desktop.enable = true` without enabling Wayland; another compatible
Wayland compositor can set `custom.desktop.wayland.enable = true` without
Hyprland. These options do not install or select an alternative compositor or
session manager. For a non-Hyprland greetd session, set `greetd.command` too.

The shared desktop baseline supplies fonts, GTK/Qt styling, Kitty, rofi,
Xcursor and failure-notification templates. The session still needs a
notification daemon. The Wayland baseline supplies Wayland tools and mako;
mako requires compositor support for layer-shell. Hyprland's own
configuration, Hyprcursor, layer blur, lock/idle/screenshot integration and
monitor rendering remain Hyprland-specific. Explicitly disabling a baseline
while enabling Hyprland is allowed, but the host then owns the missing pieces.

### Hyprland monitors

Each `custom.desktop.hyprland.monitors` entry requires `output` (an empty string
matches any output). `mode`, `position` and positive `scale` default to
`"preferred"`, `"auto"` and `1`. Optional `bitdepth` is a positive integer;
`cm` is a string and `sdrbrightness` is a nonnegative number. Mark one entry
with `hdr = true` to target it with the HDR keybind. The toggle defaults to
10-bit and `srgb` when those values are omitted, and uses brightness 1.2/1.0
for HDR/SDR as before. Extra fields are allowed as metadata, but are not
rendered and produce a warning. Multiple HDR entries also warn; the first is
used. With no monitors, the renderer emits a preferred-mode fallback.

```nix
custom.desktop.hyprland.monitors = [
  { output = "eDP-1"; }
  {
    output = "DP-1";
    mode = "2560x1440@180";
    position = "2560x0";
    scale = 1;
    bitdepth = 10;
    cm = "srgb";
    hdr = true;
  }
];
```

## Home Manager scope

Set user-specific values in `hosts/<host>/home.nix`. In the integrated setup,
Home Manager reads system feature choices through `osConfig`. Standalone Home
Manager has no `osConfig`; the desktop/media modules generally default to on,
while their own explicit options still apply.

| Prefix | Options and behavior |
| --- | --- |
| `custom.theme` | `palette` follows the NixOS palette by default, or the bundled palette standalone. An explicit Home Manager override affects that user's programs only, not system Nixvim or console colors. |
| `custom.theme.wallpaper` | `path` (nullable string), `backend` (`hyprpaper` or `mpvpaper`, default `hyprpaper`). `hyprpaper` requires Hyprland; `mpvpaper` runs on compatible layer-shell Wayland compositors, with Hyprland-only autopause. A null path disables both. |
| `custom.audio.virtualSurround` | `enable` defaults false; this is an independent Home Manager option. |
| `custom.desktop.media` | `royalPresetProfile` defaults to `balanced`. Integrated NixOS uses the **system** option and media toggle instead; the Home Manager value is for standalone use. |

Zen's `programs.zen-browser.*` options are upstream Home Manager options, not
`custom.*`. The desktop and laptop opt into a shared profile configuration with
host-specific existing paths; standalone Home Manager does not adopt a profile.
See [Zen profile adoption](zen-browser.md) before switching.

## Palette

Palette colors are `#RRGGBB` strings and `ansi` must contain exactly 16 colors.
Required roles are declared in `modules/theme/palette-type.nix`; Neovim-only
roles may be omitted and fall back to related shared colors. Additional
metadata is permitted. Nixvim maps the shared roles to Gruvbox Material,
derives its 256-color fallbacks and lualine colors, and uses the shared ANSI
list for its embedded terminal. The console uses `bg0` for color zero and the
remaining ANSI entries for colors 1–15.

As with the previous palette option, setting any part of the top-level palette
replaces its option default: an incomplete alternative palette is an error,
not an implicit mix of two schemes. To make a small change, start with the
bundled palette explicitly and override the relevant roles:

```nix
{ lib, ... }:
let
  base = import ../../modules/theme/gruvbox-material-mix-dark-medium.nix;
in
{
  custom.theme.palette = base // rec {
    red = "#e05f65";
    bg_red = red;
    ansi = lib.imap0 (i: color: if i == 1 || i == 9 then red else color) base.ansi;
  };
}
```

`//` does not recompute values already derived in `base`: update `ansi`,
`accent`, and optional roles as appropriate when changing their source colors.
For a completely different scheme, supply all required roles and all 16 ANSI
colors instead of inheriting unrelated defaults.
