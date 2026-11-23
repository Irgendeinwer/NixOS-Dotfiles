# Hermes Agent, Private Matrix Homeserver, and Ubuntu 26.04 Sandbox

`junixsrv` runs an always-on **Hermes Agent** gateway (`modules/services/hermes.nix`)
paired with a private non-federated **Continuwuity** Matrix homeserver
(`modules/services/matrix.nix`) and an isolated sibling **Ubuntu 26.04.1 LTS
(`resolute`)** `systemd-nspawn` execution container (`hermes-box`) on the
Debian 12 host.

## Architecture

- **`Continuwuity` (`https://matrix.junixsrv.internal`, `127.0.0.1:6167`):**
  Lightweight Rust + RocksDB Matrix homeserver (~30–50 MB RAM) behind `junixsrv`'s
  TLS reverse proxy. Federation, open registration, and external key-server
  lookups are disabled (`allow_federation = false`, `allow_registration = false`,
  `trusted_servers = []`). Also serves host-aware `/.well-known/matrix/client`
  and `https://100.110.103.47/_matrix/` so mobile Element clients over Tailscale
  stay on `https://100.110.103.47` without split-DNS or `/etc/hosts`.
- **`Hermes Agent` (`services.hermes-agent`, `/var/lib/hermes/.hermes`):**
  Upstream `NousResearch/hermes-agent` (`minimal` + `matrix` E2EE extras) running
  on `junixsrv`. Connects over loopback (`http://127.0.0.1:6167`) as
  `@hermes:junixsrv.internal` and responds exclusively to
  `MATRIX_ALLOWED_USERS=@julian:junixsrv.internal`.
- **Quota-aware LiteLLM routing (`http://127.0.0.1:4000/v1`):**
  - **Primary agent turns:** `gemini-4-hydrogen` (`x-litellm-session-id` sticky
    prompt-cache affinity across the 10 pooled Google AI Studio keys = 200 RPD).
  - **Overflow fallback:** `gemini-3.8-flash` (200 RPD) when primary RPD is
    exhausted.
  - **All 14 `auxiliary.*` tasks** (`compression`, `title_generation`,
    `approval`, `curator`, `background_review`, `vision`, `mcp`, etc.): pinned to
    `gemini-flash-lite` (5,000 RPD) so background housekeeping never burns
    primary reasoning quota.
- **Unlimited private search + clean page extraction:**
  - `web_search` → local loopback **SearXNG** JSON engine (`127.0.0.1:8888`,
    unlimited queries, zero external search API keys).
  - `web_extract` → **Tavily** (`TAVILY_API_KEY` injected via `sops.templates`
    from `secrets/ai.yaml`) with automatic keyless fallback.
- **Sibling Ubuntu 26.04.1 LTS (`resolute`) sandbox (`hermes-box`):**
  Hermes's `terminal` and file tools run over persistent multiplexed SSH
  (`hermes@hermes-box.local`, `/home/hermes/workspace`) inside a dedicated
  sibling `systemd-nspawn` container backed by a sparse 32 GiB ext4 loopback
  image (`/var/lib/machines/hermes-box.raw`), unprivileged user namespaces
  (`PrivateUsers=pick`), and hard cgroup v2 limits (`CPUQuota=200%`,
  `MemoryHigh=4G`, `MemoryMax=6G`, `TasksMax=2048`). `hermes-box` holds zero
  SOPS keys, zero host mounts, and zero `junixsrv` service credentials while
  giving Hermes standard FHS glibc compatibility (`sudo apt`, `uv`, `pip`, `npm`,
  `build-essential`, `git`).

## Server bootstrap (`junixsrv` + Debian 12 host)

### 1. Add `hermes_env` to `secrets/junixsrv.yaml`

Ensure `secrets/ai.yaml` is rekeyed for `&host_junixsrv` (`sops updatekeys
secrets/ai.yaml`) and store a random Matrix password for `@hermes:junixsrv.internal`
in `secrets/junixsrv.yaml`:

```bash
cd ~/dotfiles
nix shell nixpkgs#openssl nixpkgs#python3 -c bash -euo pipefail <<'EOF'
tmp="$(mktemp -d)"
trap 'shred -u "$tmp"/* 2>/dev/null || rm -f "$tmp"/*; rmdir "$tmp"' EXIT
chmod 0700 "$tmp"

bot_pw="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)"
printf 'MATRIX_PASSWORD=%s\n' "$bot_pw" > "$tmp/hermes.env"

json_val="$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' < "$tmp/hermes.env")"
sops set secrets/junixsrv.yaml '["hermes_env"]' "$json_val"
EOF

git add secrets/junixsrv.yaml
git commit -m "chore(secrets): add hermes_env for junixsrv"
git push
```

Also ensure `junixsrv`'s wildcard TLS certificate includes
`DNS:*.junixsrv.internal` and `IP:100.110.103.47` (already covered if generated
with `docs/portal.md`).

### 2. Deploy `junixsrv`

Rebuild `junixsrv` so `continuwuity.service`, `searx.service`, and
`hermes-agent.service` start and generate `/var/lib/hermes/.ssh/id_hermes_box`:

```bash
nh os switch ~/dotfiles -H junixsrv --target-host root@junixsrv.local
```

### 3. Create `@julian` and `@hermes` accounts in Continuwuity

Open registration remains disabled at all times. NixOS's `conduwuit` wrapper
already passes `--config <continuwuity.toml>`; run all account commands in one
shot ending with `--execute "server shutdown"`:

```bash
ssh -t root@junixsrv.local 'bash -euo pipefail -c '\''
  bot_pw="$(sed -n "s/^MATRIX_PASSWORD=//p" /run/secrets/hermes_env)"
  read -rsp "Choose Matrix password for @julian:junixsrv.internal: " julian_pw
  echo
  systemctl stop continuwuity.service
  sudo -Hu continuwuity conduwuit \
    --execute "users create julian $julian_pw" \
    --execute "users make_user_admin julian" \
    --execute "users create hermes $bot_pw" \
    --execute "server shutdown"
  systemctl start continuwuity.service
  systemctl restart hermes-agent.service
'\'''
```

### 4. Provision `hermes-box` on the Debian 12 `nspawn` host

Copy `scripts/provision-hermes-box.sh` to the Debian 12 host that runs
`junixsrv` and execute it as `root` (it verifies Ubuntu's archive GPG key,
auto-detects `MACVLAN=` from `/etc/systemd/nspawn/junixsrv.nspawn`, installs
`id_hermes_box.pub`, and pins `hermes-box.local`'s SSH host key into
`junixsrv`'s `/var/lib/hermes/.ssh/known_hosts`):

```bash
scp scripts/provision-hermes-box.sh root@<debian-host>:/root/
ssh root@<debian-host> 'bash /root/provision-hermes-box.sh'
```

Verify SSH sandbox connectivity from inside `junixsrv`:

```bash
ssh root@junixsrv.local \
  'sudo -Hu hermes ssh -i /var/lib/hermes/.ssh/id_hermes_box hermes@hermes-box.local "uname -a && pwd && uv --version"'
```

## Connecting Element clients

- **`junixos` & `junixbook` (`Element Desktop`):**
  `element-desktop` is installed via `custom.desktop.messaging.enable = true` and
  automatically trusts `junix-local-root-ca.pem`. Choose **Sign in → Edit
  homeserver**, enter `https://matrix.junixsrv.internal`, sign in as `julian`,
  and start a direct chat with `@hermes:junixsrv.internal`.
- **Android (`MobileF6` over Tailscale):**
  Install `assets/junix-ca.pem` in Android *Settings → Security → Encryption &
  credentials → Install a certificate → CA certificate*. Set the custom
  homeserver URL to `https://100.110.103.47` (`/.well-known/matrix/client`
  returns `https://100.110.103.47` when queried by IP and `/_matrix/` proxies
  directly to Continuwuity, requiring zero mobile DNS setup) and sign in as
  `julian`. *(Prefer **Element Classic** on Android if **Element X**'s bundled
  `rustls` verifier ignores user-installed Android CA certificates.)*

## Host CLI & diagnostics (`junixsrv`)

Your `julian` account on `junixsrv` is in the `hermes` group with
`HERMES_HOME=/var/lib/hermes/.hermes` pre-exported, so SSH sessions inspect and
share the exact same sessions, memories, and skills as Matrix:

```bash
# Gateway health & active sessions:
hermes status
hermes sessions list

# Interactive terminal UI sharing state with Matrix:
hermes --tui

# Verify loopback SearXNG JSON metasearch:
curl -fsS 'http://127.0.0.1:8888/search?q=nixos&format=json' | jq '.results[:2]'

# Follow gateway & Matrix logs:
journalctl -u hermes-agent -u continuwuity -f
```
