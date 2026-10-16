# NixOS Dotfiles

Personal NixOS and Home Manager configuration in a single flake, shared
by every machine. The whole setup is declared in Nix: boot, services,
desktop and user environment.

## Hosts

| Host        | Role    |
| :---------- | :------ |
| `junixos`   | Desktop |
| `junixbook` | Laptop  |

Hosts contribute their hardware configuration and pick the features they
use. Everything else is shared.

## Design

- Features are options under `custom.*` and default to off; hosts turn on
  what they need. A shared baseline (`modules/nixos/base.nix`) always
  applies.
- Modules are auto-imported by directory scan, so a new file needs no
  import list and must be safe to import on every host.
- Home Manager modules read the host configuration, so user setup follows
  the same feature choices as the system.
- One palette in `modules/theme/` provides every color. Programs take
  their theme from it instead of defining their own.
- Secrets are stored sops-encrypted and decrypted on the target machine.
- Inputs are pinned in `flake.lock`. Drop-in overlays placed in
  `modules/overlays/` are picked up automatically.

## Structure

```
.
├── flake.nix          # Inputs and host outputs
├── hosts/             # Hardware configuration and feature selection
├── modules/
│   ├── nixos/         # System modules and the shared baseline
│   ├── services/      # Optional services
│   ├── home-manager/  # User environment and desktop programs
│   ├── nixvim/        # Neovim configuration
│   └── theme/         # Color palette (pure data, not a module)
├── secrets/           # sops-encrypted secrets
└── assets/            # Files referenced by the configuration
```

## Usage

```bash
git clone <repo-url> ~/dotfiles
cd ~/dotfiles
sudo nixos-rebuild switch --flake .#junixos    # or .#junixbook
nix fmt                                        # format all Nix files
```

The checkout belongs in `~/dotfiles`; helper tooling points there.
Evaluating the flake needs SSH access to a private input that holds the
wallpapers.

Conventions, the commit schema and the pre-commit checks live in
[CONTRIBUTING.md](CONTRIBUTING.md).
