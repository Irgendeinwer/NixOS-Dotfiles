# Git Commit Schema

Pattern: `<type>(<scope>[/sub-scope]): <subject>`

## 1. Types (Enum)
| Type | Description |
| :--- | :--- |
| **feat** | New configuration logic or major features |
| **pkg** | Adding, removing, or swapping packages |
| **fix** | Bug fix or syntax correction |
| **chore** | Routine maintenance, `flake.lock` updates |
| **style** | Visual changes (colors, themes, formatting) |
| **refactor** | Structural changes without behavior change |
| **meta** | Changes to the repo itself (README, rules, CI) |

## 2. Scopes
*Context of the change. Use a `/` for sub-components.*
- `system`: Global NixOS config
- `hm`: Home Manager modules
- `hypr`: Hyprland (sub-scopes include: `shot`, `idle`, `lock`, `paper`)
- `flake`: Dependency management
- `zsh|nvim`: Specific program modules
- `host`: Machine-specific config

## 3. Constraints
1. **Imperative Mood**: `subject` must be "add", "fix", "update".
2. **Casing**: `subject` must start with lowercase.
3. **Punctuation**: No trailing period in `subject`.
4. **Length**: Keep it short.
