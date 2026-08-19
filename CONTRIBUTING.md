# Contributing

## Git Commit Schema

Format: `<type>([scope][/sub-scope]): <subject>`

### Types
| Type | Description |
| :--- | :--- |
| **feat** | New configuration logic, modules, or major features |
| **pkg** | Adding, removing, or updating a package in a list |
| **fix** | Bug fix, syntax correction, or hardware fix |
| **revert** | Undoing a previous commit |
| **chore** | Maintenance, `flake.lock` updates |
| **style** | Formatting, colors, themes, visual adjustments |
| **refactor** | Code restructuring without behavior changes |
| **meta** | Documentation, CI, or repo rules |

### Scopes
- `nixos`: System configuration (`nixos/kernel`, `nixos/firewall`, `nixos/base`, etc.)
- `services`: Services and daemons (`services/syncthing`, `services/immich`, etc.)
- `hm`: Home Manager modules (`hm/hypr`, `hm/theme`, `hm/zsh`, etc.)
- `host`: Machine-specific configuration (`host/junixos`, `host/junixbook`)
- `nixvim`: Neovim setup
- `flake`: Flake inputs and lockfile
- `pkgs`: Package lists and overlays

### Commit Rules
1. Imperative mood for the subject (`add`, `fix`, `update`, `refactor`).
2. Lowercase subject with no trailing period.
3. Keep commit messages concise.

---

## Workflow Rules

1. **Stage untracked files**: Nix Flakes only evaluate files tracked in git (`git add <file>`).
2. **Module convention**: New modules must use `options.custom.<namespace>.<feature>.enable = lib.mkEnableOption "..."` (default `false`).
3. **Verify before commit**: Ensure both systems evaluate cleanly:
   ```bash
   nix build .#nixosConfigurations.junixos.config.system.build.toplevel --dry-run
   nix build .#nixosConfigurations.junixbook.config.system.build.toplevel --dry-run
   nix flake check --no-build
   ```
