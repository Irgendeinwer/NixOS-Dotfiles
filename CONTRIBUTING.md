# Contributing

Rules for working in this repository, for humans and coding agents.
Keep changes small, consistent with the existing structure, and verified.

## Ground rules

- Flakes only see git-tracked files: `git add` new files before evaluating.
- Format all Nix code with the repo formatter (`nix fmt`); CI rejects unformatted files.
- Before committing, all hosts must evaluate:
  - `nix build .#nixosConfigurations.junixos.config.system.build.toplevel --dry-run`
  - `nix build .#nixosConfigurations.junixbook.config.system.build.toplevel --dry-run`
  - `nix build .#nixosConfigurations.junixsrv.config.system.build.toplevel --dry-run`
  - `nix flake check --no-build`
  - `nix build .#checks.x86_64-linux.nightly-runtime .#checks.x86_64-linux.remote-builder-mdns`
  - `nix build .#checks.x86_64-linux.container-options .#checks.x86_64-linux.remote-builder-options .#checks.x86_64-linux.build-server-options .#checks.x86_64-linux.without-userns-filter`
  - `nix build .#checks.x86_64-linux.desktop-options .#checks.x86_64-linux.standalone-home .#checks.x86_64-linux.theme-options .#checks.x86_64-linux.zen-options`
  - The individual check targets can be built separately to reduce evaluation memory, as CI does.
- Prefer packages from nixpkgs; do not vendor, download or version-pin upstream tools without a concrete reason.
- Use sops-encrypted files under `secrets/` for new secrets. The existing opt-in ARK friend-server configuration is a deliberate legacy exception; leave it unchanged unless its owner requests otherwise.

## Modules

- Custom options live under `custom.<domain>.<feature>` (domains: `system`, `desktop`, `hardware`, `services`, `theme`, `audio`). See [docs/options.md](docs/options.md) for their scopes and exceptions.
- Feature modules generally expose `options.custom.<...>.enable` (default off); preserve and document deliberate default-on or derived defaults. A nested name alone does not imply a parent gate.
- Modules are auto-imported (`modules/default.nix` and `modules/home-manager/default.nix`): adding a `.nix` module is enough. The scanner skips every `default.nix` and symlink; pure data and helpers belong outside scanned directories, e.g. `modules/theme/` or `lib/`.
- Host files (`hosts/<host>/`) contain only toggles and host-specific facts. Shared behaviour belongs in `modules/`; refer to the host through options, not by importing host files.
- Home Manager modules read host toggles through `osConfig` where behaviour depends on them; standalone Home Manager (no `osConfig`) must still evaluate with its documented defaults.
- Themed programs take their colours from `custom.theme.palette`; do not add hardcoded theme colours. A palette override must contain all required roles and 16 ANSI entries.
- Whatever a feature toggle installs or opens, its consumers respect the same toggle: autostarts, firewall ports and dependent config live behind it too.
- For existing Zen profiles, follow the backup and collision checks in [docs/zen-browser.md](docs/zen-browser.md) before activating.

## Commits

- Format: `<type>([scope][/sub-scope]): <subject>`
- Types: `feat`, `fix`, `style`, `refactor`, `chore`, `pkg`, `revert`, `meta`.
- Common scopes: `nixos`, `services[/name]`, `hm[/area]`, `host/<host>`, `nixvim`, `flake`, `pkgs`. Omit the scope only for truly global changes.
- Imperative mood, lowercase subject, no trailing period, concise.
- One logical change per commit. Keep history linear and clean: amend or rewrite unmerged commits instead of stacking fixups on top of mistakes.
