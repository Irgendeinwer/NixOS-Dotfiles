# Server portal, custom scripts, and local PKI

`junixsrv` hosts an HTTPS overview dashboard and modular reverse proxy on TCP
`443` (with TCP `80` redirecting to HTTPS), backed by a declarative private
Root CA (`assets/junix-ca.pem`) and a single private flake input
(`Irgendeinwer/nix-private`) for private scripts and small projects.

## Architecture

- **Nginx + static Gruvbox frontend (`modules/services/portal.nix`):**
  Colors are derived from `custom.theme.palette`, and static assets are served
  with a strict `Content-Security-Policy` (`script-src 'self'; style-src 'self'`).
  User-facing web apps (`navidrome`, `vikunja`, `radicale`, `continuwuity`) bind
  strictly to `127.0.0.1` and are exposed over HTTPS `:443` via dedicated
  subdomain virtual hosts (`https://music.junixsrv.internal`,
  `https://tasks.junixsrv.internal`, `https://cal.junixsrv.internal`,
  `https://matrix.junixsrv.internal`). Direct-port infrastructure cards
  (`harmonia` on `:5000`) resolve against `window.location.hostname`.
- **Unified LAN + Tailscale hostname aliases:**
  `junixos` maps `junixsrv.internal` and `*.junixsrv.internal` to `junixsrv`'s
  discovered LAN IPv4 address via `custom.system.remoteBuilder.extraHostAliases`
  (`remote-builder-mdns.py`), while `junixbook` maps the exact same hostnames
  to `100.110.103.47` via `custom.services.tailscale.peers`. Both machines use
  identical `https://*.junixsrv.internal` URLs seamlessly.
- **Mobile raw-IP HTTPS paths (`MobileF6`):**
  Because Android lacks per-app `/etc/hosts` without MagicDNS, the default
  `https://100.110.103.47` virtual host also proxies `/music/rest/` +
  `/music/share/` to Navidrome (configure Symfonium/Tempo server URL as
  `https://100.110.103.47/music`), `/cal/` (`X-Script-Name: /cal`) to Radicale
  (configure DAVx5 base URL as `https://100.110.103.47/cal/`), and `/_matrix/`
  + `/.well-known/matrix/client` to Continuwuity (configure Element Android /
  Element X homeserver URL as `https://100.110.103.47`).
- **Internal-only Syncthing, LiteLLM, SearXNG, and Hermes Agent cards:**
  Syncthing's GUI (`127.0.0.1:8384`), LiteLLM (`127.0.0.1:4000`), SearXNG
  (`127.0.0.1:8888`), and Hermes Agent remain internal-only. Their cards display
  live unit health and one-click SSH tunnel or diagnostic snippets.
- **Read-only status daemon (`modules/services/scripts/portal-status.py`):**
  `junix-portal-status.service` runs as the unprivileged `junix-portal` user on
  `127.0.0.1:18080` and exposes `GET /api/status` (proxied at `= /api/status`).
  It reads `/proc`, cgroup v2 memory limits (`memory.current` / `memory.max`),
  disk free space, allowlisted `systemctl show` unit states, and the sanitized
  `/var/lib/nix-nightly-status/status.json` summary. `/var/lib/nix-nightly`
  (`0700` root) and `last-run.log` (`0600` root) remain inaccessible to the web
  stack.

## Adding scripts and small projects

### Public CLI scripts (`pkgs/scripts/`)

Drop `<name>.sh` or `<name>.py` into `pkgs/scripts/` and add an entry in
`pkgs/scripts/default.nix` using `mkShellScript` (ShellCheck) or
`mkPythonScript` (Ruff + bytecode check, `pythonPackages`, `runtimeInputs`).
Every entry is exposed automatically as `pkgs.custom.<name>`,
`nix run .#<name>`, and checked by `checks.x86_64-linux.custom-scripts`.

### Small web projects on `junixsrv`

Register loopback web services under `custom.services.portal.projects.<name>`
(either in `hosts/junixsrv/configuration.nix` for public projects or inside
`nix-private`'s `nixosModules.junixsrv` for private ones):

```nix
custom.services.portal.projects.study-tracker = {
  title = "Study Tracker";
  description = "Timetable and exam tracker";
  port = 18090;
  execStart = "${lib.getExe pkgs.private.study-tracker}";
  environment.LOG_LEVEL = "info";
};
```

When `execStart` is set, `portal.nix` creates `portal-project-<name>.service`
with `HOST=127.0.0.1`, `PORT=<port>`, and `/var/lib/portal-projects/<name>`,
proxies `https://junixsrv.<local|internal>/study-tracker/` to
`127.0.0.1:18090`, and adds a live-monitored card under **Projects**.

### Private repository (`Irgendeinwer/nix-private`)

`flake.nix` wires `inputs.private` (`git+ssh://git@github.com/Irgendeinwer/nix-private.git`)
into overlays (`overlays.default`), NixOS (`nixosModules.default` and
`nixosModules.<host>`), Home Manager (`homeManagerModules.default` and
`homeManagerModules.<host>`), and `packages.x86_64-linux`. All outputs are
optional:

```nix
# Starter flake.nix in Irgendeinwer/nix-private
{
  description = "Private scripts and junixsrv projects";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages.${system} = { };
      overlays.default = final: prev: { private = { }; };
      nixosModules.junixsrv = { ... }: { };
      homeManagerModules.default = { ... }: { };
    };
}
```

Because GitHub forbids reusing one SSH deploy key across two repositories and
accepts the first matching deploy key offered on `github.com`:

- **GitHub Actions** (`.github/workflows/nix-{test,update}.yml`) writes
  `WALLPAPER_DEPLOY_KEY` and `NIX_PRIVATE_DEPLOY_KEY` to isolated SSH host
  aliases (`github-wallpaper`, `github-nix-private`) with `IdentitiesOnly yes`
  and Git `insteadOf` rules for both `ssh://git@github.com/...` and
  `git@github.com:...`.
- **`junixsrv` (`nix-nightly-update`)** uses
  `custom.services.buildServer.nightly.extraDeployKeys` to generate per-repo SSH
  host aliases and Git `insteadOf` rules from `nix_private_deploy_key` in
  `secrets/junixsrv.yaml`.

## Bootstrapping and rotating the local Root CA

`modules/nixos/pki.nix` trusts `assets/junix-ca.pem` system-wide on every NixOS
host (`security.pki.certificateFiles`), `modules/home-manager/zen-browser.nix`
installs it into Zen Browser via `policies.Certificates`, and
`modules/home-manager/pki.nix` seeds `~/.pki/nssdb` via `certutil` so
Chromium/Electron apps (such as Feishin pointed at
`https://music.junixsrv.internal`) trust HTTPS automatically. Keep the Root CA
private key in `secrets/pki.yaml` (encrypted strictly to `*user_julian` in
`.sops.yaml`, so no host key can decrypt it and `secrets/users/julian.yaml`
stays reserved for `user_ssh_key`).

```bash
cd ~/dotfiles
nix shell nixpkgs#openssl -c bash -euo pipefail <<'EOF'
ca_tmp="$(mktemp -d)"
trap 'shred -u "$ca_tmp"/* 2>/dev/null || rm -f "$ca_tmp"/*; rmdir "$ca_tmp"' EXIT
chmod 0700 "$ca_tmp"

json_quote() {
  python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' < "$1"
}

# 1. Generate 10-year ECDSA P-256 Root CA
openssl ecparam -name prime256v1 -genkey -noout -out "$ca_tmp/junix-ca.key"
openssl req -x509 -new -key "$ca_tmp/junix-ca.key" -sha256 -days 3650 \
  -subj "/CN=Junix Internal Root CA/O=Junix" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash" \
  -out assets/junix-ca.pem

# 2. Issue 825-day leaf certificate for junixsrv (LAN + Tailscale SANs)
openssl ecparam -name prime256v1 -genkey -noout -out "$ca_tmp/portal.key"
openssl req -new -key "$ca_tmp/portal.key" \
  -subj "/CN=junixsrv.internal/O=Junix" \
  -out "$ca_tmp/portal.csr"

cat > "$ca_tmp/portal-ext.cnf" <<'EXT'
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:*.junixsrv.internal, DNS:junixsrv.internal, DNS:junixsrv.local, DNS:junixsrv, IP:100.110.103.47
EXT

openssl x509 -req -in "$ca_tmp/portal.csr" \
  -CA assets/junix-ca.pem -CAkey "$ca_tmp/junix-ca.key" \
  -CAcreateserial -CAserial "$ca_tmp/junix-ca.srl" \
  -out "$ca_tmp/portal-fullchain.pem" -days 825 -sha256 \
  -extfile "$ca_tmp/portal-ext.cnf"
cat assets/junix-ca.pem >> "$ca_tmp/portal-fullchain.pem"

# 3. Store Root CA key in user-only sops (secrets/pki.yaml) and leaf cert/key in junixsrv sops
if [ ! -f secrets/pki.yaml ]; then
  printf 'junix_ca_key: ""\n' > "$ca_tmp/pki-init.yaml"
  sops --encrypt --filename-override secrets/pki.yaml \
    "$ca_tmp/pki-init.yaml" > secrets/pki.yaml
fi
sops set secrets/pki.yaml '["junix_ca_key"]' "$(json_quote "$ca_tmp/junix-ca.key")"
sops set secrets/junixsrv.yaml '["portal_tls_cert"]' "$(json_quote "$ca_tmp/portal-fullchain.pem")"
sops set secrets/junixsrv.yaml '["portal_tls_key"]' "$(json_quote "$ca_tmp/portal.key")"
EOF

git add assets/junix-ca.pem secrets/pki.yaml secrets/junixsrv.yaml
```

To trust HTTPS on `MobileF6` (Android): copy `assets/junix-ca.pem` to the phone
and install it via *Settings → Security & privacy → More security settings →
Encryption & credentials → Install a certificate → CA certificate*.
