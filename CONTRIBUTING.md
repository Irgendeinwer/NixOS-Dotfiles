# Git Commit Schema

Pattern: `<type>([scope][/sub-scope])[!]: <subject>`

## 1. Types (Enum)
| Type | Description |
| :--- | :--- |
| **feat** | New configuration logic, new `.nix` modules, or major features |
| **pkg** | Simply adding, removing, or swapping a package in a list |
| **fix** | Bug fix, syntax correction, or hardware/driver fixes |
| **revert** | Undoing a previous commit |
| **chore** | Routine maintenance, `flake.lock` updates |
| **style** | Visual changes (colors, themes, formatting, wallpapers) |
| **refactor** | Structural changes (moving files) without behavior change |
| **meta** | Changes to the repo itself (README, rules, CI) |

## 2. Breaking Changes (`!`)
If a change requires manual intervention (e.g., deleting a cache, manual folder moves, or a major version upgrade that breaks old syntax), add a `!` after the scope.
- *Example:* `feat(hm/zsh)!: migrate to new plugin system`

## 3. Scopes
*Context of the change. Use `/` for sub-components.*
- `nixos`: Global NixOS system logic
- `hm`: Home Manager modules (e.g., `hm/mpv`, `hm/hypr/paper`)
- `host`: Machine-specific config (e.g., `host/junixos`, `host/junixbook`)
- `flake`: Dependency and lockfile management
- `pkgs`: One-off package installs or custom derivations

## 4. Constraints & Logic
1. **Imperative Mood**: `subject` must be "add", "fix", "update", "migrate", etc.
2. **Casing & Punctuation**: `subject` starts lowercase; no trailing period.
3. **Logic vs. Lists**:
   - Use **pkg** for one-liners: `pkg(hm): add vlc`
   - Use **feat** for new modules/logic: `feat(hm/mpv): add module with custom scripts`
4. **Single-Line "Why"**: 
   - Since no body is used, include the "why" in the subject if it's not obvious.
   - *Example:* `fix(nixos): disable module to prevent boot loop`
   - Keep it concise.
