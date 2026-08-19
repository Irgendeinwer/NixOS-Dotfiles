# NixOS Dotfiles

Personal Flake-based NixOS and Home Manager configurations.

## Hosts

- **`junixos`**: Desktop workstation
- **`junixbook`**: Laptop

## Structure

```
.
├── flake.nix          # Inputs, overlays, and host outputs
├── hosts/             # Machine configurations (hardware + toggles)
├── modules/
│   ├── default.nix    # Recursive auto-importer for NixOS and services
│   ├── nixos/         # System modules and shared baseline
│   ├── services/      # Service modules
│   ├── home-manager/  # User environment and desktop modules
│   ├── nixvim/        # Neovim configuration
│   └── overlays/      # Nixpkgs overlays
└── assets/            # Additional files
```

## Architecture

- **Custom Namespace**: All custom configuration options use `custom.<domain>.<feature>` (`custom.system.*`, `custom.desktop.*`, `custom.services.*`, `custom.theme.*`).
- **Auto-Importing**: `modules/default.nix` and `modules/home-manager/default.nix` dynamically discover all `.nix` files. Modules default to disabled (`enable = false`).
- **Shared Base**: Common system configurations (locale, bootloader, user accounts, shell, core packages, and baseline firewall) are centralized in `modules/nixos/base.nix`.
