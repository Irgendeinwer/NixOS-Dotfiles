{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.custom.services.portal;
  user = config.custom.user or "julian";
  p = config.custom.theme.palette or (import ../theme/gruvbox-material-mix-dark-medium.nix);
  inherit (import ../theme/lib.nix { inherit lib; }) rgba;

  sopsFile = ../../secrets + "/${config.networking.hostName}.yaml";
  useSopsTls = cfg.enable && cfg.tls.enable && cfg.tls.certificateFile == null;
  tlsCertPath =
    if cfg.tls.certificateFile != null then
      "${cfg.tls.certificateFile}"
    else if useSopsTls then
      config.sops.secrets.portal_tls_cert.path
    else
      "/run/secrets/portal_tls_cert";
  tlsKeyPath =
    if cfg.tls.keyFile != null then
      "${cfg.tls.keyFile}"
    else if useSopsTls then
      config.sops.secrets.portal_tls_key.path
    else
      "/run/secrets/portal_tls_key";

  nightlyEnabled =
    (config.custom.services.buildServer.enable or false)
    && (config.custom.services.buildServer.nightly.enable or false);

  reservedLocations = [
    "/"
    "/index.html"
    "/style.css"
    "/app.js"
    "/portal-config.json"
    "/icon.svg"
    "/api/status"
  ];

  validProjectName = name: builtins.match "[a-z0-9][a-z0-9_-]{0,22}" name != null;

  activeServices = lib.filterAttrs (_: s: s.enable) cfg.services;
  activeProjects = lib.filterAttrs (_: prj: prj.enable) cfg.projects;

  projectLocation = name: prj: if prj.location != null then prj.location else "/${name}/";
  projectUnit =
    name: prj:
    if prj.systemdUnit != null then
      prj.systemdUnit
    else if prj.execStart != null then
      "portal-project-${name}.service"
    else
      null;
  projectProxyPass =
    prj:
    if prj.stripPrefix then
      "http://127.0.0.1:${toString prj.port}/"
    else
      "http://127.0.0.1:${toString prj.port}";

  serviceCards = lib.mapAttrsToList (id: s: {
    inherit id;
    inherit (s)
      title
      description
      category
      badge
      icon
      order
      systemdUnit
      hintCommand
      location
      port
      scheme
      path
      url
      ;
  }) activeServices;

  projectCards = lib.mapAttrsToList (name: prj: {
    id = "project-${name}";
    title = if prj.title != null then prj.title else name;
    inherit (prj)
      description
      badge
      icon
      order
      ;
    category = prj.category;
    systemdUnit = projectUnit name prj;
    hintCommand = null;
    location = projectLocation name prj;
    port = null;
    scheme = "https";
    path = "/";
    url = null;
  }) activeProjects;

  allCards = serviceCards ++ projectCards;

  proxiedServiceLocations = lib.mapAttrs' (
    _: s:
    lib.nameValuePair s.location {
      proxyPass = s.proxyPass;
      proxyWebsockets = s.proxyWebsockets;
    }
  ) (lib.filterAttrs (_: s: s.proxyPass != null && s.location != null) activeServices);

  proxiedProjectLocations = lib.mapAttrs' (
    name: prj:
    lib.nameValuePair (projectLocation name prj) {
      proxyPass = projectProxyPass prj;
      proxyWebsockets = prj.proxyWebsockets;
    }
  ) activeProjects;

  allProxyLocations =
    map (s: s.location) (
      builtins.filter (s: s.proxyPass != null && s.location != null) (builtins.attrValues activeServices)
    )
    ++ lib.mapAttrsToList projectLocation activeProjects;

  managedProjects = lib.filterAttrs (_: prj: prj.execStart != null) activeProjects;

  cardUnits = builtins.filter (u: u != null) (map (c: c.systemdUnit) allCards);
  trackedUnits = lib.unique (cardUnits ++ cfg.monitoredUnits);

  portalConfigJson = pkgs.writeText "portal-config.json" (
    builtins.toJSON {
      hostName = config.networking.hostName;
      inherit nightlyEnabled;
      services = allCards;
      infraUnits = cfg.monitoredUnits;
    }
  );

  styleCss = pkgs.writeText "portal-style.css" ''
    :root {
      --bg-dim: ${p.bg_dim};
      --bg0: ${p.bg0};
      --bg1: ${p.bg1};
      --bg2: ${p.bg2};
      --bg3: ${p.bg3};
      --bg-word: ${if p.bg_current_word != null then p.bg_current_word else p.bg2};
      --fg0: ${p.fg0};
      --fg1: ${p.fg1};
      --grey0: ${p.grey0};
      --grey1: ${p.grey1};
      --grey2: ${p.grey2};
      --accent: ${p.accent};
      --green: ${p.green};
      --aqua: ${p.aqua};
      --blue: ${p.blue};
      --yellow: ${p.yellow};
      --orange: ${p.orange};
      --red: ${p.red};
      --purple: ${p.purple};
      --border: ${rgba p.grey0 "0.28"};
      --border-hover: ${rgba p.accent "0.55"};
      --card-shadow: 0 10px 28px rgba(0, 0, 0, 0.24);
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }

    body {
      min-height: 100vh;
      background-color: var(--bg-dim);
      background-image:
        radial-gradient(circle at 12% 0%, ${rgba p.aqua "0.08"}, transparent 42%),
        radial-gradient(circle at 88% 4%, ${rgba p.accent "0.07"}, transparent 38%);
      color: var(--fg0);
      font-family: ui-sans-serif, system-ui, -apple-system, "Inter", "Segoe UI", sans-serif;
      line-height: 1.5;
      padding: 2rem 1.25rem 3rem;
    }

    .shell {
      max-width: 1120px;
      margin: 0 auto;
      display: flex;
      flex-direction: column;
      gap: 1.75rem;
    }

    .topbar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 1rem;
      padding: 1.25rem 1.5rem;
      background: var(--bg0);
      border: 1px solid var(--border);
      border-radius: 14px;
      box-shadow: var(--card-shadow);
    }

    .brand {
      display: flex;
      align-items: center;
      gap: 0.95rem;
    }

    .brand-logo {
      width: 42px;
      height: 42px;
      border-radius: 10px;
      background: var(--bg1);
      padding: 6px;
      border: 1px solid var(--border);
    }

    .brand-title {
      font-size: 1.35rem;
      font-weight: 700;
      letter-spacing: -0.02em;
      color: var(--fg0);
    }

    .brand-subtitle {
      font-size: 0.84rem;
      color: var(--grey2);
      font-family: ui-monospace, "JetBrains Mono", monospace;
    }

    .topbar-actions {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.6rem;
    }

    .pill {
      display: inline-flex;
      align-items: center;
      gap: 0.42rem;
      font-size: 0.76rem;
      font-weight: 600;
      font-family: ui-monospace, "JetBrains Mono", monospace;
      padding: 0.28rem 0.65rem;
      border-radius: 999px;
      background: var(--bg1);
      color: var(--grey2);
      border: 1px solid var(--border);
      white-space: nowrap;
    }

    .pill[data-secure="true"] {
      color: var(--aqua);
      border-color: ${rgba p.aqua "0.35"};
    }

    .pill[data-tone="ok"] {
      color: var(--green);
      border-color: ${rgba p.green "0.38"};
      background: ${rgba p.green "0.10"};
    }

    .pill[data-tone="info"] {
      color: var(--blue);
      border-color: ${rgba p.blue "0.38"};
      background: ${rgba p.blue "0.10"};
    }

    .pill[data-tone="active"] {
      color: var(--aqua);
      border-color: ${rgba p.aqua "0.42"};
      background: ${rgba p.aqua "0.12"};
    }

    .pill[data-tone="warn"] {
      color: var(--yellow);
      border-color: ${rgba p.yellow "0.42"};
      background: ${rgba p.yellow "0.12"};
    }

    .pill[data-tone="crit"] {
      color: var(--red);
      border-color: ${rgba p.red "0.45"};
      background: ${rgba p.red "0.12"};
    }

    .dot {
      width: 7px;
      height: 7px;
      border-radius: 50%;
      background: currentColor;
    }

    .btn {
      background: var(--bg1);
      color: var(--fg0);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 0.34rem 0.75rem;
      font-size: 0.8rem;
      font-weight: 600;
      cursor: pointer;
      transition: border-color 140ms ease, background 140ms ease;
    }

    .btn:hover {
      background: var(--bg2);
      border-color: var(--border-hover);
    }

    .vitals-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(235px, 1fr));
      gap: 1rem;
    }

    .vital-card {
      background: var(--bg0);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 1.05rem 1.2rem;
      display: flex;
      flex-direction: column;
      gap: 0.45rem;
    }

    .vital-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.5rem;
    }

    .vital-label {
      font-size: 0.78rem;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      color: var(--grey1);
      font-weight: 700;
    }

    .vital-primary {
      font-size: 1.22rem;
      font-weight: 700;
      font-family: ui-monospace, "JetBrains Mono", monospace;
      color: var(--fg0);
    }

    .vital-secondary {
      font-size: 0.78rem;
      color: var(--grey2);
    }

    .bar-track {
      height: 6px;
      width: 100%;
      background: var(--bg2);
      border-radius: 999px;
      overflow: hidden;
      margin-top: 0.2rem;
    }

    .bar-fill {
      height: 100%;
      width: 0%;
      border-radius: 999px;
      background: var(--green);
      transition: width 260ms ease;
    }

    .bar-fill[data-tone="warn"] {
      background: var(--yellow);
    }

    .bar-fill[data-tone="crit"] {
      background: var(--red);
    }

    .nightly-details {
      margin-top: 0.25rem;
      font-size: 0.76rem;
      color: var(--grey2);
    }

    .nightly-details summary {
      cursor: pointer;
      color: var(--accent);
      font-weight: 600;
      user-select: none;
    }

    .nightly-summary-list {
      margin-top: 0.4rem;
      padding-left: 1rem;
      font-family: ui-monospace, "JetBrains Mono", monospace;
      font-size: 0.73rem;
      display: flex;
      flex-direction: column;
      gap: 0.18rem;
    }

    .services-root {
      display: flex;
      flex-direction: column;
      gap: 1.5rem;
    }

    .category-section {
      display: flex;
      flex-direction: column;
      gap: 0.75rem;
    }

    .category-title {
      font-size: 0.85rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--grey2);
      padding-left: 0.15rem;
    }

    .cards-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(310px, 1fr));
      gap: 1rem;
    }

    .service-card {
      display: flex;
      flex-direction: column;
      gap: 0.65rem;
      padding: 1.2rem 1.3rem;
      background: var(--bg0);
      border: 1px solid var(--border);
      border-radius: 13px;
      text-decoration: none;
      color: inherit;
      transition: transform 140ms ease, border-color 140ms ease, background 140ms ease;
    }

    a.service-card:hover {
      transform: translateY(-2px);
      background: var(--bg1);
      border-color: var(--border-hover);
    }

    .service-card--internal {
      border-style: dashed;
    }

    .card-top {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.6rem;
    }

    .card-icon {
      width: 36px;
      height: 36px;
      border-radius: 9px;
      background: var(--bg1);
      border: 1px solid var(--border);
      color: var(--accent);
      display: inline-flex;
      align-items: center;
      justify-content: center;
    }

    .card-icon svg {
      width: 19px;
      height: 19px;
    }

    .card-badges {
      display: flex;
      flex-wrap: wrap;
      gap: 0.4rem;
      justify-content: flex-end;
    }

    .card-title {
      font-size: 1.06rem;
      font-weight: 700;
      color: var(--fg0);
    }

    .card-desc {
      font-size: 0.85rem;
      color: var(--grey2);
      flex: 1;
    }

    .card-target {
      margin-top: 0.25rem;
      padding-top: 0.6rem;
      border-top: 1px solid var(--border);
      display: flex;
      align-items: center;
      justify-content: space-between;
      font-family: ui-monospace, "JetBrains Mono", monospace;
      font-size: 0.76rem;
      color: var(--aqua);
    }

    .card-arrow {
      font-size: 0.9rem;
      color: var(--accent);
    }

    .card-hint {
      margin-top: 0.25rem;
      padding: 0.45rem 0.6rem;
      background: var(--bg-dim);
      border: 1px solid var(--border);
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.5rem;
    }

    .card-hint-code {
      font-family: ui-monospace, "JetBrains Mono", monospace;
      font-size: 0.72rem;
      color: var(--grey2);
      overflow-x: auto;
      white-space: nowrap;
    }

    .copy-btn {
      background: var(--bg2);
      color: var(--fg0);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 0.2rem 0.5rem;
      font-size: 0.72rem;
      font-weight: 600;
      cursor: pointer;
      flex-shrink: 0;
    }

    .copy-btn:hover {
      border-color: var(--border-hover);
    }

    .footer-bar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 0.8rem;
      padding: 0.95rem 1.25rem;
      background: var(--bg0);
      border: 1px solid var(--border);
      border-radius: 12px;
    }

    .footer-label {
      font-size: 0.76rem;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      color: var(--grey1);
      font-weight: 700;
    }

    .infra-units {
      display: flex;
      flex-wrap: wrap;
      gap: 0.5rem;
    }

    .infra-chip {
      display: inline-flex;
      align-items: center;
      gap: 0.38rem;
      padding: 0.24rem 0.6rem;
      border-radius: 999px;
      font-family: ui-monospace, "JetBrains Mono", monospace;
      font-size: 0.74rem;
      background: var(--bg1);
      border: 1px solid var(--border);
      color: var(--grey2);
    }

    .infra-chip[data-tone="ok"] .dot {
      color: var(--green);
    }

    .infra-chip[data-tone="warn"] .dot {
      color: var(--yellow);
    }

    .infra-chip[data-tone="crit"] {
      border-color: ${rgba p.red "0.45"};
      color: var(--red);
    }

    .infra-name {
      color: var(--fg0);
      font-weight: 600;
    }
  '';

  indexHtml = pkgs.writeText "portal-index.html" ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>${config.networking.hostName} · Overview</title>
      <link rel="icon" type="image/svg+xml" href="/icon.svg">
      <link rel="stylesheet" href="/style.css">
    </head>
    <body>
      <main class="shell">
        <header class="topbar">
          <div class="brand">
            <img class="brand-logo" src="/icon.svg" alt="">
            <div>
              <h1 id="host-title" class="brand-title">${config.networking.hostName}</h1>
              <p id="host-subtitle" class="brand-subtitle">NixOS · loading telemetry…</p>
            </div>
          </div>
          <div class="topbar-actions">
            <span id="connection-pill" class="pill">Connecting…</span>
            <span id="refresh-state" class="pill" data-tone="muted">Syncing</span>
            <button id="refresh-btn" class="btn" type="button">Refresh</button>
          </div>
        </header>

        <section class="vitals-grid" aria-label="System vitals">
          <div class="vital-card">
            <div class="vital-head">
              <span class="vital-label">CPU Load</span>
            </div>
            <div id="cpu-primary" class="vital-primary">—</div>
            <div id="cpu-secondary" class="vital-secondary">—</div>
            <div class="bar-track"><div id="cpu-bar" class="bar-fill"></div></div>
          </div>

          <div class="vital-card">
            <div class="vital-head">
              <span class="vital-label">Memory</span>
            </div>
            <div id="mem-primary" class="vital-primary">—</div>
            <div id="mem-secondary" class="vital-secondary">—</div>
            <div class="bar-track"><div id="mem-bar" class="bar-fill"></div></div>
          </div>

          <div class="vital-card">
            <div class="vital-head">
              <span class="vital-label">Nix Store &amp; Disk</span>
            </div>
            <div id="disk-primary" class="vital-primary">—</div>
            <div id="disk-secondary" class="vital-secondary">—</div>
            <div class="bar-track"><div id="disk-bar" class="bar-fill"></div></div>
          </div>

          <div class="vital-card">
            <div class="vital-head">
              <span class="vital-label">Nightly Updates</span>
              <span id="nightly-badge" class="pill">…</span>
            </div>
            <div id="nightly-primary" class="vital-primary">—</div>
            <div id="nightly-secondary" class="vital-secondary">—</div>
            <details id="nightly-details" class="nightly-details" hidden>
              <summary>Run summary</summary>
              <ul id="nightly-summary-list" class="nightly-summary-list"></ul>
            </details>
          </div>
        </section>

        <div id="services-root" class="services-root"></div>

        <footer class="footer-bar">
          <span class="footer-label">Core Daemons</span>
          <div id="infra-units" class="infra-units"></div>
        </footer>
      </main>
      <script src="/app.js"></script>
    </body>
    </html>
  '';

  webRoot = pkgs.runCommand "junix-portal-webroot" { } ''
    mkdir -p "$out"
    ln -s ${indexHtml} "$out/index.html"
    ln -s ${styleCss} "$out/style.css"
    ln -s ${./scripts/portal-app.js} "$out/app.js"
    ln -s ${portalConfigJson} "$out/portal-config.json"
    ln -s ${../../assets/icon.svg} "$out/icon.svg"
  '';

  serviceSubmodule = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to display (and, if configured, proxy) this service entry.";
      };

      title = lib.mkOption {
        type = lib.types.nonEmptyStr;
        description = "Display title shown on the overview card.";
      };

      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Short description displayed on the card.";
      };

      category = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "Services";
        description = "Section heading under which this card is grouped.";
      };

      badge = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Optional compact tag shown on the card (for example `TCP 4533`).";
      };

      icon = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "globe";
        description = "Built-in icon identifier (`music`, `sync`, `package`, `code`, `globe`).";
      };

      order = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Sort priority within its category (lower numbers appear first).";
      };

      systemdUnit = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Optional systemd unit queried for live health on the card.";
      };

      hintCommand = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = ''
          Optional CLI snippet displayed on internal-only (non-linked) cards;
          `{host}` is replaced in the browser with the active hostname.
        '';
      };

      location = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Portal subpath (starting with `/`) to link to and optionally reverse-proxy.";
      };

      proxyPass = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Optional upstream URL for Nginx `proxy_pass` at `location`.";
      };

      proxyWebsockets = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Forward WebSocket upgrade headers when `proxyPass` is set.";
      };

      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = ''
          Direct service TCP port resolved dynamically against the browser's
          current hostname (`junixsrv.local` on LAN vs `junixsrv.internal` on Tailscale).
        '';
      };

      scheme = lib.mkOption {
        type = lib.types.enum [
          "http"
          "https"
        ];
        default = "http";
        description = "URL scheme used when linking to `port`.";
      };

      path = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "/";
        description = "URL path appended when linking to `port`.";
      };

      url = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Explicit static URL when linking to an external address.";
      };
    };
  };

  projectSubmodule = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable, reverse-proxy, and list this project.";
      };

      title = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Card title (defaults to the project attribute name).";
      };

      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Short description displayed on the landing page.";
      };

      category = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "Projects";
        description = "Section heading under which this project card is grouped.";
      };

      badge = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = "Project";
        description = "Compact tag displayed on the project card.";
      };

      icon = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "code";
        description = "Built-in icon identifier.";
      };

      order = lib.mkOption {
        type = lib.types.int;
        default = 200;
        description = "Sort priority within its category.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        description = "Loopback TCP port (`127.0.0.1:<port>`) where the project listens.";
      };

      location = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Nginx subpath (defaults to `/<name>/`).";
      };

      stripPrefix = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Strip `location` prefix when proxying to `127.0.0.1:<port>/`.";
      };

      proxyWebsockets = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Forward WebSocket upgrade headers to the project.";
      };

      execStart = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = ''
          Optional command to supervise as `portal-project-<name>.service`
          with `HOST=127.0.0.1` and `PORT=<port>`. Leave null when managed by a
          separate systemd unit.
        '';
      };

      workingDirectory = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Working directory for the managed service (defaults to `/var/lib/portal-project-<name>`).";
      };

      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Extra environment variables passed to the managed project service.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional sops environment file passed to the managed project service.";
      };

      systemdUnit = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Systemd unit monitored on the card (defaults to `portal-project-<name>.service` when `execStart` is set).";
      };
    };
  };

  statusUnitFlags = lib.concatMap (u: [
    "--unit"
    u
  ]) trackedUnits;
in
{
  options.custom.services.portal = {
    enable = lib.mkEnableOption "HTTPS overview dashboard, status API, and modular reverse proxy";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open HTTP (TCP 80) and, when TLS is enabled, HTTPS (TCP 443) in the firewall.";
    };

    serverName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "Primary Nginx virtualHost name (marked as the default vhost).";
    };

    serverAliases = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [
        "${config.networking.hostName}.local"
        "${config.networking.hostName}.internal"
      ];
      defaultText = lib.literalExpression ''[ "<hostName>.local" "<hostName>.internal" ]'';
      description = "Additional server names served by the portal virtual host.";
    };

    statusPort = lib.mkOption {
      type = lib.types.port;
      default = 18080;
      description = "Loopback TCP port for the internal read-only JSON status daemon.";
    };

    monitoredUnits = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [
        "sshd.service"
        "nginx.service"
        "nix-daemon.socket"
      ]
      ++ lib.optional (config.services.tailscale.enable or false) "tailscaled.service";
      defaultText = lib.literalExpression ''[ "sshd.service" "nginx.service" ... ]'';
      description = "Core infrastructure systemd units displayed in the portal footer.";
    };

    tls = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Serve the portal over HTTPS on TCP 443 and redirect HTTP on TCP 80.
          Uses `portal_tls_cert` and `portal_tls_key` from the host's sops
          secrets file unless `certificateFile` and `keyFile` are set explicitly.
        '';
      };

      certificateFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Explicit TLS certificate PEM path; null reads `portal_tls_cert` from sops.";
      };

      keyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Explicit TLS private key PEM path; null reads `portal_tls_key` from sops.";
      };
    };

    services = lib.mkOption {
      type = lib.types.attrsOf serviceSubmodule;
      default = { };
      description = "Service cards and optional reverse-proxy routes shown on the landing page.";
    };

    projects = lib.mkOption {
      type = lib.types.attrsOf projectSubmodule;
      default = { };
      description = "Small web projects supervised on loopback and reverse-proxied under the portal.";
    };
  };

  config = lib.mkMerge [
    # Default service cards when the matching repository services are enabled on the host.
    {
      custom.services.portal.services = {
        navidrome = lib.mkIf (config.custom.services.navidrome.enable or false) {
          title = lib.mkDefault "Navidrome";
          description = lib.mkDefault "Self-hosted music streaming server and Subsonic API";
          category = lib.mkDefault "Media & Sync";
          badge = lib.mkDefault "TCP ${toString (config.custom.services.navidrome.port or 4533)}";
          icon = lib.mkDefault "music";
          port = lib.mkDefault (config.custom.services.navidrome.port or 4533);
          path = lib.mkDefault "/app/";
          systemdUnit = lib.mkDefault "navidrome.service";
          order = lib.mkDefault 10;
        };

        syncthing = lib.mkIf (config.custom.services.syncthing.enable or false) {
          title = lib.mkDefault "Syncthing";
          description = lib.mkDefault "P2P folder sync; web GUI bound to loopback only";
          category = lib.mkDefault "Media & Sync";
          badge = lib.mkDefault "127.0.0.1:8384";
          icon = lib.mkDefault "sync";
          systemdUnit = lib.mkDefault "syncthing.service";
          hintCommand = lib.mkDefault "ssh -N -L 8384:127.0.0.1:8384 ${user}@{host}";
          order = lib.mkDefault 20;
        };

        harmonia = lib.mkIf (config.custom.services.buildServer.enable or false) {
          title = lib.mkDefault "Harmonia Cache";
          description = lib.mkDefault "Signed Nix binary cache serving pre-built host closures";
          category = lib.mkDefault "Infrastructure";
          badge = lib.mkDefault "TCP 5000";
          icon = lib.mkDefault "package";
          port = lib.mkDefault 5000;
          path = lib.mkDefault "/nix-cache-info";
          systemdUnit = lib.mkDefault "harmonia.service";
          order = lib.mkDefault 30;
        };
      };
    }

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = (cfg.tls.certificateFile == null) == (cfg.tls.keyFile == null);
          message = "custom.services.portal.tls: certificateFile and keyFile must either both be set or both be null (sops-backed).";
        }
        {
          assertion = lib.all validProjectName (builtins.attrNames cfg.projects);
          message = "custom.services.portal.projects: names must match [a-z0-9][a-z0-9_-]{0,22}.";
        }
        {
          assertion = lib.all (
            s:
            let
              targets =
                lib.optional (s.location != null) "location"
                ++ lib.optional (s.port != null) "port"
                ++ lib.optional (s.url != null) "url";
            in
            (s.proxyPass != null -> s.location != null) && builtins.length targets <= 1
          ) (builtins.attrValues activeServices);
          message = "custom.services.portal.services: each entry may set at most one of location, port, or url, and proxyPass requires location.";
        }
        {
          assertion = lib.all (
            loc: lib.hasPrefix "/" loc && !(builtins.elem loc reservedLocations)
          ) allProxyLocations;
          message = "custom.services.portal: proxied service/project locations must start with '/' and not collide with reserved portal paths.";
        }
        {
          assertion = lib.all (
            name:
            let
              prj = activeProjects.${name};
            in
            prj.stripPrefix -> lib.hasSuffix "/" (projectLocation name prj)
          ) (builtins.attrNames activeProjects);
          message = "custom.services.portal.projects: location must end with '/' when stripPrefix is true.";
        }
        {
          assertion = builtins.length allProxyLocations == builtins.length (lib.unique allProxyLocations);
          message = "custom.services.portal: duplicate Nginx location across services/projects.";
        }
        {
          assertion =
            let
              projectPorts = map (prj: prj.port) (builtins.attrValues activeProjects);
            in
            !(builtins.elem cfg.statusPort projectPorts)
            && builtins.length projectPorts == builtins.length (lib.unique projectPorts);
          message = "custom.services.portal.projects: project ports must be unique and must not collide with statusPort.";
        }
      ];

      users.groups = {
        junix-portal = { };
      }
      // lib.mapAttrs' (name: _: lib.nameValuePair "portal-${name}" { }) managedProjects;

      users.users = {
        junix-portal = {
          isSystemUser = true;
          group = "junix-portal";
        };
      }
      // lib.mapAttrs' (
        name: _:
        lib.nameValuePair "portal-${name}" {
          isSystemUser = true;
          group = "portal-${name}";
        }
      ) managedProjects;

      sops.secrets = lib.mkIf useSopsTls {
        portal_tls_cert = {
          inherit sopsFile;
          key = "portal_tls_cert";
          owner = config.services.nginx.user;
          group = config.services.nginx.group;
          mode = "0400";
          reloadUnits = [ "nginx.service" ];
        };
        portal_tls_key = {
          inherit sopsFile;
          key = "portal_tls_key";
          owner = config.services.nginx.user;
          group = config.services.nginx.group;
          mode = "0400";
          reloadUnits = [ "nginx.service" ];
        };
      };

      networking.firewall = lib.mkIf cfg.openFirewall {
        allowedTCPPorts = [ 80 ] ++ lib.optional cfg.tls.enable 443;
      };

      services.nginx = {
        enable = true;
        recommendedProxySettings = lib.mkDefault true;
        recommendedTlsSettings = lib.mkDefault true;
        recommendedOptimisation = lib.mkDefault true;
        recommendedGzipSettings = lib.mkDefault true;

        virtualHosts.${cfg.serverName} = {
          default = true;
          inherit (cfg) serverAliases;
          forceSSL = cfg.tls.enable;
          sslCertificate = lib.mkIf cfg.tls.enable tlsCertPath;
          sslCertificateKey = lib.mkIf cfg.tls.enable tlsKeyPath;
          root = "${webRoot}";
          extraConfig = lib.optionalString cfg.tls.enable ''
            ssl_stapling off;
          '';
          locations = {
            "/" = {
              index = "index.html";
              tryFiles = "$uri $uri/ =404";
              extraConfig = ''
                add_header X-Content-Type-Options "nosniff" always;
                add_header X-Frame-Options "DENY" always;
                add_header Referrer-Policy "no-referrer" always;
                add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self';" always;
              '';
            };
            "= /api/status" = {
              proxyPass = "http://127.0.0.1:${toString cfg.statusPort}/api/status";
              extraConfig = ''
                add_header X-Content-Type-Options "nosniff" always;
              '';
            };
          }
          // proxiedServiceLocations
          // proxiedProjectLocations;
        };
      };

      systemd.services = {
        junix-portal-status = {
          description = "Read-only JSON status daemon for junixsrv overview portal";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            User = "junix-portal";
            Group = "junix-portal";
            ExecStart = utils.escapeSystemdExecArgs (
              [
                (lib.getExe pkgs.python3)
                "-B"
                "${./scripts/portal-status.py}"
                "--bind"
                "127.0.0.1"
                "--port"
                (toString cfg.statusPort)
                "--hostname"
                config.networking.hostName
                "--nightly-enabled"
                (if nightlyEnabled then "1" else "0")
                "--systemctl"
                "${config.systemd.package}/bin/systemctl"
              ]
              ++ statusUnitFlags
            );
            Restart = "on-failure";
            RestartSec = "2s";
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            PrivateUsers = !config.boot.isContainer;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
          };
        };
      }
      // lib.mapAttrs' (
        name: prj:
        lib.nameValuePair "portal-project-${name}" {
          description = "Managed portal web project (${name})";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          environment = {
            HOST = "127.0.0.1";
            PORT = toString prj.port;
          }
          // prj.environment;
          serviceConfig = {
            User = "portal-${name}";
            Group = "portal-${name}";
            StateDirectory = "portal-project-${name}";
            StateDirectoryMode = "0700";
            WorkingDirectory =
              if prj.workingDirectory != null then prj.workingDirectory else "/var/lib/portal-project-${name}";
            ExecStart = prj.execStart;
            Restart = "on-failure";
            RestartSec = "3s";
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            PrivateUsers = !config.boot.isContainer;
            ProtectSystem = "strict";
            ProtectHome = true;
          }
          // lib.optionalAttrs (prj.environmentFile != null) {
            EnvironmentFile = prj.environmentFile;
          };
        }
      ) managedProjects;
    })
  ];
}
