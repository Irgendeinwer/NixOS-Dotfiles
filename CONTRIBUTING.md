# Contributing

Rules for working in this repository, for humans and coding agents.
Keep changes small, consistent with the existing structure, and verified.

## Ground rules

- Flakes only see git-tracked files: `git add` new files before evaluating.
- Format all Nix code with the repo formatter (`nix fmt`); CI rejects unformatted files.
- Before committing, both hosts must evaluate:
  - `nix build .#nixosConfigurations.junixos.config.system.build.toplevel --dry-run`
  - `nix build .#nixosConfigurations.junixbook.config.system.build.toplevel --dry-run`
  - `nix flake check --no-build`
- Prefer packages from nixpkgs; do not vendor, download or version-pin upstream tools without a concrete reason.
- Never commit plaintext secrets. Secrets are sops-encrypted files under `secrets/`.

## Modules

- Custom options live under `custom.<domain>.<feature>` (domains: `system`, `desktop`, `hardware`, `services`, `theme`, `audio`).
- Feature modules expose `options.custom.<...>.enable` (default off) unless they are unconditional by nature: the shared base, palette consumers, tools that work under any compositor.
- Modules are auto-imported (`modules/default.nix` and `modules/home-manager/default.nix`): adding a `.nix` file is enough. Pure data must not live in auto-imported directories; it belongs in `modules/theme/`.
- Host files (`hosts/<host>/`) contain only toggles and host-specific facts. Shared behaviour belongs in `modules/`; refer to the host through options, not by importing host files.
- Home Manager modules read host toggles through `osConfig` where behaviour depends on them; standalone Home Manager (no `osConfig`) must still evaluate, defaulting to on.
- Themed programs take all colours from `custom.theme.palette`; never hardcode colour values.
- Whatever a feature toggle installs or opens, its consumers respect the same toggle: autostarts, firewall ports and dependent config live behind it too.

## Commits

- Format: `<type>([scope][/sub-scope]): <subject>`
- Types: `feat`, `fix`, `style`, `refactor`, `chore`, `pkg`, `revert`, `meta`.
- Common scopes: `nixos`, `services[/name]`, `hm[/area]`, `host/<host>`, `nixvim`, `flake`, `pkgs`. Omit the scope only for truly global changes.
- Imperative mood, lowercase subject, no trailing period, concise.
- One logical change per commit. Keep history linear and clean: amend or rewrite unmerged commits instead of stacking fixups on top of mistakes.
