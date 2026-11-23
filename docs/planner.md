# Planner, Tasks, Calendar, and Barless Day Engine

`junixsrv` runs a self-hosted planning stack behind HTTPS (`:443`), paired with
an offline-first **Day Engine** (`plan`) tailored to `junixos` and `junixbook`'s
barless Hyprland desktop.

## Architecture

- **`Vikunja` (`https://tasks.junixsrv.internal`, `127.0.0.1:3456`):**
  Handles quick to-dos, projects (`#uni`, `#home`, `Inbox`), priorities, due
  dates, Kanban/Gantt web views, and native parent/subtask step hierarchies
  (`relation_kind = "subtask"`). Self-registration and public link sharing are
  disabled by default (`modules/services/planner.nix`).
- **`Radicale` (`https://cal.junixsrv.internal`, `127.0.0.1:5232`):**
  Handles RFC 5545 `VEVENT` appointments, locations, recurring schedules
  (`RRULE` / `EXDATE`), and standards-compliant CalDAV sync (`bcrypt` htpasswd
  auth, per-user collection isolation). Also exposed at
  `https://100.110.103.47/cal/` (`X-Script-Name: /cal`) for mobile `DAVx5`.
- **Offline-first Day Engine (`pkgs/scripts/plan.py`):**
  Stores tasks, steps, appointments, focus state, and an idempotent write-back
  queue (`dirty_op`) in `~/.local/share/junix-plan/state.db` (SQLite WAL). Every
  action on `junixos` or `junixbook` works in `<15ms` offline (for example on a
  train without Wi-Fi) and reconciles automatically via
  `junix-plan-daemon.service` when `junixsrv` is reachable.

## Server bootstrap (`junixsrv`)

1. Ensure `junixsrv`'s TLS certificate includes the wildcard SAN
   `DNS:*.junixsrv.internal` (see `docs/portal.md`).
2. Add `vikunja_env` and `radicale_htpasswd` to `secrets/junixsrv.yaml`:

```bash
cd ~/dotfiles
nix shell nixpkgs#openssl nixpkgs#apacheHttpd -c bash -euo pipefail <<'EOF'
tmp="$(mktemp -d)"
trap 'shred -u "$tmp"/* 2>/dev/null || rm -f "$tmp"/*; rmdir "$tmp"' EXIT
chmod 0700 "$tmp"

json_quote() {
  python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' < "$1"
}

printf 'VIKUNJA_SERVICE_SECRET=%s\n' "$(openssl rand -hex 32)" > "$tmp/vikunja.env"
# Prompts interactively on /dev/tty for your Radicale CalDAV password (bcrypt cost 12):
htpasswd -nBC 12 irgendeinwer > "$tmp/radicale.htpasswd"

sops set secrets/junixsrv.yaml '["vikunja_env"]' "$(json_quote "$tmp/vikunja.env")"
sops set secrets/junixsrv.yaml '["radicale_htpasswd"]' "$(json_quote "$tmp/radicale.htpasswd")"
EOF
```

3. Deploy `junixsrv`, then create your Vikunja account (since open web
   registration is disabled):

```bash
ssh -t root@junixsrv.local \
  'set -a && . /run/secrets/vikunja_env && set +a && cd /var/lib/vikunja && exec sudo -E -Hu vikunja vikunja user create --username irgendeinwer --email irgendeinwer@junix.internal'
```

4. Sign in at `https://tasks.junixsrv.internal`, open *Settings → API Tokens*,
   and create a token with read/write permissions on **projects**, **tasks**, and
   **task relations** for `plan`.

## Desktop & laptop setup (`junixos` / `junixbook`)

Run `plan auth` once per machine to save `~/.config/junix-plan/credentials.env`
(`0600`) and run an initial sync:

```bash
plan auth
plan sync
```

### Barless Hyprland workflow

| Shortcut / Command | Surface | Behavior |
| :--- | :--- | :--- |
| `SUPER + A` | **Rofi Day Hub** | Interactive timeline showing active Focus banner, free-gap summary, today's hard appointments, auto-slotted task steps (`[1/3]`, `~25m`), and open backlog. |
| `SUPER + SHIFT + A` | **Instant Capture** | Single-line natural-language popup (`+` task / `@` appointment) that commits immediately to SQLite and syncs in the background. |
| `SUPER + T` | **Pulse HUD** | Upgraded barless status check: shows clock, active Focus countdown, next appointment, next slotted step, and open count (uses `-a notify-send` so it displays even during manual DND). |
| `hyprlock` (top-center) | **Agenda Pill** | Reads `$XDG_RUNTIME_DIR/junix-plan-lock.txt` in `<0.5ms` with zero network/Python latency on lock. |

### Inside `SUPER + A` (`plan rofi`)

- Type directly into the prompt starting with `+` or `@` and press **Enter** to
  capture without leaving the hub.
- **Enter** on a task/step toggles completion (`✓`) or completes an active Focus
  block; **Alt+Enter** opens the full task action menu; **Alt+1** starts a timed
  **Focus** session on the selected task/step (automatically enabling Mako DND
  and restoring your prior DND state when the step finishes); **Alt+2** snoozes
  `+15m`; **Alt+3** decomposes a large task into timed `>>` steps
  (`Step 1 ~25m >> Step 2 ~35m`); **Alt+4** syncs now.

### Quick-capture examples

```text
+ Prepare OS sheet tomorrow 18:00 !high #uni >> Read notes ~25m >> Implement ~45m >> Test ~20m
+ Call landlord fri 10:00 ~15m !med #home
@ Dentist 24.11.2026 14:30-15:15 @City_Clinic
@ Weekly Seminar mon 10:15 90m @Room_2.04 weekly
```

### Notification & DND etiquette

- **Hard appointments (`T-15m` & `T-0m`)** fire with `urgency=critical`, so
  they pierce Mako's `do-not-disturb` mode and never let you miss a fixed
  meeting while focusing.
- **Soft step nudges** use `app-name=junix-plan` (`urgency=normal`) with
  actionable **Start Focus**, **Done**, and **Snooze +15m** buttons, and stay
  silent whenever DND is active.

## Mobile setup (`MobileF6`)

- **Calendar (`DAVx5`):** Add account with *Base URL and user name* →
  `https://100.110.103.47/cal/`, username `irgendeinwer`, and your Radicale password.
  All appointments sync bidirectionally with Android's native Calendar app.
- **Music (`Symfonium` / `Tempo`):** Server URL `https://100.110.103.47/music`
  (Subsonic `/music/rest/` HTTPS proxy).
