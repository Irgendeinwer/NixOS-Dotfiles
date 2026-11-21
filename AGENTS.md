# Coding agent guide

This is a personal NixOS flake with shared system and Home Manager modules.
Read [CONTRIBUTING.md](CONTRIBUTING.md) for conventions and the required
checks, and [docs/options.md](docs/options.md) before changing option behavior.
Follow the user's current instructions and preserve existing host behavior and
data unless a change is explicitly requested.

## Repository map

- `flake.nix` declares the pinned inputs, `mkHost`, host configurations,
  formatter and checks. Each host selects hardware and features in `hosts/`.
- `modules/default.nix` scans `modules/nixos/` and `modules/services/`;
  `modules/home-manager/default.nix` scans its own directory. The shared
  scanner in `lib/scan-paths.nix` recursively imports regular `.nix` files and
  skips every `default.nix` and symlink. Scanned files must be safe on every
  host. Put pure data, helpers, and explicitly imported profile modules outside
  scanned directories, e.g. `modules/theme/`, `modules/zen/`, or `lib/`.
- `modules/nixvim/` configures system-wide Neovim; `modules/theme/` defines
  the shared palette and color helpers; `pkgs/` contains local packages and
  standalone CLI tools (`pkgs/scripts/` built via `pkgs/mk-script.nix`).
  `tests/` contains Nix option evaluations and isolated runtime tests.
- `docs/` contains feature-specific operation and recovery procedures. Keep
  the root README introductory; put detailed behavior and safety procedures
  with the feature, and update this guide when project-wide conventions change.

## Configuration changes

- Inspect existing option declarations and consumers before changing gates.
  Nesting is not a dependency: independently controlled options must remain
  independent unless a real dependency is documented. Distinguish an
  overridable default from a forced parent gate.
- NixOS options live in the system module graph; Home Manager user options
  live in its separate graph. Integrated Home Manager receives `osConfig` and
  `inputs`; standalone Home Manager may not have `osConfig`. Preserve its
  documented defaults and test both applicable modes. Host-specific facts
  belong in `hosts/`, not hardcoded into shared modules.
- The desktop, Wayland and Hyprland baselines have distinct scopes. Keep
  compositor-specific services, commands and autostarts behind the appropriate
  gate; non-Hyprland sessions must not accidentally require Hyprland.
- Derive theme colors from `custom.theme.palette` rather than new hardcoded
  literals. System Nixvim follows the system palette; Home Manager follows it
  by default but can override its user palette separately. Validate complete
  palettes, their 16 ANSI colors, optional roles and consumer fallbacks.
- Prefer narrow, compatible types and assertions for values that consumers
  actually require. Preserve intentional extension points; do not silently
  discard unknown data or change unrelated options merely for consistency.
- Treat existing user profiles, browser registries, databases, state and
  activation collisions as data to preserve. Before changing an adoption or
  migration, read its feature guide (e.g. [Zen](docs/zen-browser.md)), inspect
  upstream activation behavior and add regression coverage. Never activate,
  delete or replace user data in the agent environment without authorization.
- Home Manager activation checks before `writeBoundary` must be read-only;
  mutating phases must honor `DRY_RUN`, recheck collisions, and handle locking
  and recovery. Distinguish application-owned writable state from immutable
  Nix assets, and never silently replace an unrecognized file or foreign link.
  Pin external assets to immutable revisions and hashes, and document any
  application-managed update path that can change them after activation.
- Use sops for new secrets. Do not print, copy into the Nix store, or commit
  private values. The existing opt-in ARK friend-server configuration is an
  owner-approved legacy exception; leave it unchanged unless requested.

## Verification and Git

- Git flakes see tracked files only: stage new files before testing, or use a
  temporary `path:` checkout that includes them. Do not accidentally stage
  unrelated user work. The private `wallpaper` and `private` (`nix-private`)
  inputs require the owner's SSH access; if unavailable, an explicitly labeled
  temporary input override can test evaluation only, not private content or a
  real build. Do not commit test placeholders or change `flake.lock` just to
  work around missing access.
- Run the formatter and the host, flake and explicit checks listed in
  [CONTRIBUTING.md](CONTRIBUTING.md). `nix flake check --no-build` evaluates
  checks but does not run their builders. If resources are limited, evaluate
  hosts and checks separately, and report precisely what was and was not run.
  The CI workflow in `.github/workflows/nix-test.yml` is the other source of
  truth for required checks.
- Run isolated shell/Python tests when appropriate; avoid real deployments,
  destructive cleanup, or long-running services as a side effect of tests.
  Report environment-dependent failures rather than presenting a partial
  evaluation as a successful build.
- Work on the current branch. Do not commit or push unless requested; follow
  the repository's commit format and do not add unsolicited authorship
  trailers. Never expose credentials or modify unrelated changes.
