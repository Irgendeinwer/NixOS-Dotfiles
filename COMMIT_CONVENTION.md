# Git Commit Schema

Pattern: `<type>(<scope>): <subject>`

## 1. Types (Enum)
| Type | Description |
| :--- | :--- |
| **feat** | New feature or configuration logic |
| **fix** | Bug fix or syntax correction |
| **chore** | Routine maintenance, `flake.lock` updates |
| **style** | Visual changes (colors, assets, formatting) |
| **refactor** | Code restructuring without behavior change |
| **perf** | Performance optimization |
| **docs** | Documentation changes only |

## 2. Scopes
*Context of the change.*
- `system`: Global NixOS config (`configuration.nix`)
- `hm`: Home Manager modules
- `hypr`: Hyprland/Wayland config
- `flake`: Dependency management
- `zsh|nvim`: Specific program modules
- `host`: Machine-specific config (e.g., `junixos`)

## 3. Constraints
1. **Imperative Mood**: `subject` must be "add", "fix", "update" (not "added", "fixed").
2. **Casing**: `subject` must start with lowercase.
3. **Punctuation**: No trailing period in `subject`.
4. **Length**: Max 72 characters.
5. **Atomicity**: One logical change per commit.

## Examples
> feat(hypr): migrate to windowrule v1 syntax
> chore(flake): update inputs
> fix(audio): resolve pipewire latency
> style(waybar): remove background shadow
