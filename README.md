# NixOS Dotfiles

Personal NixOS and Home Manager configuration in a single flake, shared
by every machine. The whole setup is declared in Nix: boot, services,
desktop and user environment.

## Hosts

| Host        | Role    |
| :---------- | :------ |
| `junixos`   | Desktop |
| `junixbook` | Laptop  |
| `junixsrv`  | Server  |

Hosts contribute their hardware configuration and pick the features they
use. Everything else is shared.

## Design

- Most features are options under `custom.*` and default to off; a few
  tools default on, and desktop/Wayland defaults follow Hyprland. A shared
  baseline (`modules/nixos/base.nix`) always applies. See the
  [options and scope guide](docs/options.md).
- Modules are auto-imported by directory scan, so a new module needs no
  import list and must be safe to import on every host. Shared helpers live
  outside the scanned directories.
- Home Manager modules read host choices through `osConfig`, keeping
  user-level services aligned with the system.
- One palette in `modules/theme/` supplies the system, Home Manager and
  Nixvim themes; hosts can provide another complete palette.
- Secrets generally use sops and are decrypted on the target machine.
- Inputs are pinned in `flake.lock`. Drop-in overlays placed in
  `modules/overlays/` are picked up automatically.

## Structure

```
.
├── flake.nix         # Inputs and host outputs
├── hosts/            # Hardware configuration and feature selection
├── lib/              # Shared scanner, renderers and activation helpers
├── modules/
│   ├── nixos/        # System modules and the shared baseline
│   ├── services/     # Optional services
│   ├── home-manager/ # User environment and desktop programs
│   ├── nixvim/       # Neovim configuration
│   └── theme/        # Color palette (pure data, not a module)
├── pkgs/             # Local package definitions
├── tests/            # Runtime and module-option regression checks
├── secrets/          # sops-encrypted secrets
└── assets/           # Files referenced by the configuration
```

## Usage

Before activating a configuration that adopts existing application data,
back it up and follow the relevant guide in `docs/`.

```bash
git clone <repo-url> ~/dotfiles
cd ~/dotfiles
sudo nixos-rebuild switch --flake .#junixos    # or .#junixbook
nix fmt                                        # format all Nix files
```

The checkout belongs in `~/dotfiles`; helper tooling points there.
Evaluating the flake needs SSH access to a private input that holds the
wallpapers.

## Documentation

- [Contributing](CONTRIBUTING.md) — conventions and checks.
- [Custom options](docs/options.md) — scopes, defaults and composition.
- [Application data](docs/zen-browser.md) — Zen profile adoption and backups.
- [Tailscale](docs/tailscale.md) — private access to `junixsrv` on the LAN and remotely.
- [Recovery](docs/recovery.md) — reinstall and recovery steps.
- [Agent guide](AGENTS.md) — repository-specific guidance for coding agents.
