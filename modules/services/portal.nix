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
    "/favicon.svg"
    "/api/status"
  ];

  validProjectName = name: builtins.match "[a-z0-9][a-z0-9_-]{0,22}" name != null;
  validSubdomain = name: builtins.match "[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?" name != null;

  activeServices = lib.filterAttrs (_: s: s.enable) cfg.services;
  activeProjects = lib.filterAttrs (_: prj: prj.enable) cfg.projects;
  subdomainServices = lib.filterAttrs (_: s: s.subdomain != null) activeServices;

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
      path
      url
      ;
    vhost = if s.subdomain != null then "${s.subdomain}.${cfg.domainSuffix}" else null;
    scheme = if s.subdomain != null then (if cfg.tls.enable then "https" else "http") else s.scheme;
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
    vhost = null;
    port = null;
    scheme = "https";
    path = "/";
    url = null;
  }) activeProjects;

  allCards = serviceCards ++ projectCards;

  proxiedServiceLocations = lib.mapAttrs' (
    _: s:
    lib.nameValuePair s.location (
      {
        proxyPass = s.proxyPass;
        proxyWebsockets = s.proxyWebsockets;
      }
      // lib.optionalAttrs (s.extraProxyConfig != "") {
        extraConfig = s.extraProxyConfig;
      }
    )
  ) (lib.filterAttrs (_: s: s.proxyPass != null && s.location != null) activeServices);

  proxiedProjectLocations = lib.mapAttrs' (
    name: prj:
    lib.nameValuePair (projectLocation name prj) {
      proxyPass = projectProxyPass prj;
      proxyWebsockets = prj.proxyWebsockets;
    }
  ) activeProjects;

  subdomainVirtualHosts = lib.mapAttrs' (
    _: s:
    lib.nameValuePair "${s.subdomain}.${cfg.domainSuffix}" {
      forceSSL = cfg.tls.enable;
      sslCertificate = lib.mkIf cfg.tls.enable tlsCertPath;
      sslCertificateKey = lib.mkIf cfg.tls.enable tlsKeyPath;
      extraConfig = lib.optionalString cfg.tls.enable ''
        ssl_stapling off;
      '';
      locations."/" = {
        proxyPass = s.proxyPass;
        proxyWebsockets = s.proxyWebsockets;
      }
      // lib.optionalAttrs (s.extraProxyConfig != "") {
        extraConfig = s.extraProxyConfig;
      };
    }
  ) subdomainServices;

  allProxyLocations =
    map (s: s.location) (
      builtins.filter (s: s.proxyPass != null && s.location != null) (builtins.attrValues activeServices)
    )
    ++ lib.mapAttrsToList projectLocation activeProjects
    ++ builtins.attrNames cfg.extraLocations;

  allSubdomains = map (s: s.subdomain) (builtins.attrValues subdomainServices);

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

  optColor = c: fb: if c != null then c else fb;
  bg2Color = optColor (p.bg2 or null) p.bg1;
  bgVisualGreen = optColor (p.bg_visual_green or null) (rgba p.green "0.18");
  bgVisualBlue = optColor (p.bg_visual_blue or null) (rgba p.aqua "0.18");
  bgVisualPurple = optColor (p.bg_visual_purple or null) (rgba p.purple "0.18");

  nixSnowflakePaths = ''
    <path d="M7.352 1.592l-1.364.002L5.32 2.75l1.557 2.713-3.137-.008-1.32 2.34H14.11l-1.353-2.332-3.192-.006-2.214-3.865z" fill="${p.blue}" />
    <path d="M13.527 1.592l-2.687.025 5.846 10.127 1.341-2.34-1.59-2.765 2.24-3.85-.683-1.182h-1.336l-1.57 2.705-1.56-2.72z" fill="${p.green}" />
    <path d="M20.414 5.787l-5.846 10.125 2.696-.008 1.601-2.76 4.453.016.682-1.183-.666-1.157-3.13-.008L21.778 8.1l-1.365-2.313z" fill="${p.yellow}" />
    <path d="M9.432 8.086l-2.696.008-1.601 2.76-4.453-.016L0 12.02l.666 1.157 3.13.008-1.575 2.71 1.365 2.315L9.432 8.086z" fill="${p.orange}" />
    <path d="M7.33 12.25l-.006.01-.002-.004-1.342 2.34 1.59 2.765-2.24 3.85.684 1.182H7.35l.004-.006h.001l1.567-2.698 1.558 2.72 2.688-.026-.004-.006h.01L7.33 12.25z" fill="${p.red}" />
    <path d="M9.882 16.18l1.354 2.332 3.192.006 2.215 3.865 1.363-.002.668-1.156-1.557-2.713 3.137.008 1.32-2.34H9.881Z" fill="${p.purple}" />
  '';

  faviconSvg = pkgs.writeText "portal-favicon.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
      <rect width="32" height="32" rx="7" fill="${p.bg1}" stroke="${p.bg5}" stroke-width="1.5"/>
      <g transform="translate(4 4)">
        ${nixSnowflakePaths}
      </g>
    </svg>
  '';

  iconSvgs = {
    music = pkgs.writeText "portal-icon-music.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
        <circle cx="12" cy="12" r="9.5" fill="${p.bg0}" stroke="${p.orange}" stroke-width="1.6"/>
        <path d="M6.8 8.5A6.3 6.3 0 0 1 15.5 6.8" stroke="${p.grey0}" stroke-width="1.2" stroke-linecap="round"/>
        <path d="M8.5 17.2A6.3 6.3 0 0 0 17.2 15.5" stroke="${p.grey0}" stroke-width="1.2" stroke-linecap="round"/>
        <circle cx="12" cy="12" r="3.6" fill="${p.orange}"/>
        <circle cx="12" cy="12" r="1.3" fill="${p.bg0}"/>
        <circle cx="18.5" cy="5.5" r="2" fill="${p.yellow}"/>
        <path d="M18.5 7.5 L15.6 11.2" stroke="${p.fg0}" stroke-width="1.5" stroke-linecap="round"/>
      </svg>
    '';
    sync = pkgs.writeText "portal-icon-sync.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
        <circle cx="12" cy="12" r="8.6" stroke="${p.blue}" stroke-width="1.6"/>
        <line x1="13.6" y1="12.8" x2="18.6" y2="7.2" stroke="${p.aqua}" stroke-width="1.6" stroke-linecap="round"/>
        <line x1="13.6" y1="12.8" x2="18.2" y2="17.8" stroke="${p.aqua}" stroke-width="1.6" stroke-linecap="round"/>
        <line x1="13.6" y1="12.8" x2="4.2" y2="13.6" stroke="${p.aqua}" stroke-width="1.6" stroke-linecap="round"/>
        <circle cx="13.6" cy="12.8" r="2.2" fill="${p.fg0}"/>
        <circle cx="18.6" cy="7.2" r="2.1" fill="${p.aqua}" stroke="${p.bg0}" stroke-width="0.9"/>
        <circle cx="18.2" cy="17.8" r="2.1" fill="${p.blue}" stroke="${p.bg0}" stroke-width="0.9"/>
        <circle cx="4.2" cy="13.6" r="2.1" fill="${p.aqua}" stroke="${p.bg0}" stroke-width="0.9"/>
      </svg>
    '';
    package = pkgs.writeText "portal-icon-package.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
        ${nixSnowflakePaths}
      </svg>
    '';
    code = pkgs.writeText "portal-icon-code.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="8 7 3 12 8 17" stroke="${p.yellow}" stroke-width="1.9"/>
        <polyline points="16 7 21 12 16 17" stroke="${p.yellow}" stroke-width="1.9"/>
        <line x1="13.8" y1="5.5" x2="10.2" y2="18.5" stroke="${p.orange}" stroke-width="1.8"/>
      </svg>
    '';
    globe = pkgs.writeText "portal-icon-globe.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="9" stroke="${p.purple}" stroke-width="1.7"/>
        <line x1="3.4" y1="12" x2="20.6" y2="12" stroke="${p.purple}" stroke-width="1.5"/>
        <path d="M12 3a13.8 13.8 0 0 1 3.6 9 13.8 13.8 0 0 1-3.6 9 13.8 13.8 0 0 1-3.6-9A13.8 13.8 0 0 1 12 3z" stroke="${p.fg0}" stroke-width="1.5"/>
      </svg>
    '';
    tasks = pkgs.writeText "portal-icon-tasks.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <rect x="3.5" y="3.5" width="17" height="17" rx="4" fill="${p.bg0}" stroke="${p.green}" stroke-width="1.6"/>
        <polyline points="7.5 10.2 9.4 12.1 12.8 8.4" stroke="${p.green}" stroke-width="1.8"/>
        <line x1="14.8" y1="10.3" x2="17.2" y2="10.3" stroke="${p.fg0}" stroke-width="1.6"/>
        <circle cx="9.2" cy="15.5" r="1.2" fill="${p.yellow}"/>
        <line x1="12.6" y1="15.5" x2="17.2" y2="15.5" stroke="${p.grey1}" stroke-width="1.6"/>
      </svg>
    '';
    calendar = pkgs.writeText "portal-icon-calendar.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <rect x="3.5" y="5" width="17" height="15.5" rx="3.5" fill="${p.bg0}" stroke="${p.orange}" stroke-width="1.6"/>
        <line x1="8" y1="3.2" x2="8" y2="6.6" stroke="${p.fg0}" stroke-width="1.7"/>
        <line x1="16" y1="3.2" x2="16" y2="6.6" stroke="${p.fg0}" stroke-width="1.7"/>
        <line x1="3.8" y1="9.6" x2="20.2" y2="9.6" stroke="${p.orange}" stroke-width="1.5"/>
        <circle cx="8.6" cy="13.6" r="1.3" fill="${p.yellow}"/>
        <circle cx="12" cy="13.6" r="1.3" fill="${p.aqua}"/>
        <circle cx="15.4" cy="13.6" r="1.3" fill="${p.grey1}"/>
        <circle cx="8.6" cy="17" r="1.3" fill="${p.grey1}"/>
        <circle cx="12" cy="17" r="1.3" fill="${p.green}"/>
      </svg>
    '';
    chat = pkgs.writeText "portal-icon-chat.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <path d="M4 5.5A2.5 2.5 0 0 1 6.5 3h11A2.5 2.5 0 0 1 20 5.5v8A2.5 2.5 0 0 1 17.5 16H9.8L5.2 19.8A.7.7 0 0 1 4 19.3V5.5z" fill="${p.bg0}" stroke="${p.aqua}" stroke-width="1.6"/>
        <circle cx="8.6" cy="9.6" r="1.2" fill="${p.aqua}"/>
        <circle cx="12" cy="9.6" r="1.2" fill="${p.fg0}"/>
        <circle cx="15.4" cy="9.6" r="1.2" fill="${p.green}"/>
      </svg>
    '';
    bot = pkgs.writeText "portal-icon-bot.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <line x1="12" y1="3.2" x2="12" y2="6.2" stroke="${p.yellow}" stroke-width="1.7"/>
        <circle cx="12" cy="2.7" r="1.2" fill="${p.yellow}"/>
        <rect x="4.5" y="6.2" width="15" height="13.3" rx="3.5" fill="${p.bg0}" stroke="${p.purple}" stroke-width="1.6"/>
        <circle cx="9.3" cy="11.8" r="1.4" fill="${p.aqua}"/>
        <circle cx="14.7" cy="11.8" r="1.4" fill="${p.aqua}"/>
        <line x1="9" y1="15.8" x2="15" y2="15.8" stroke="${p.fg0}" stroke-width="1.6"/>
      </svg>
    '';
  };

  styleCss = pkgs.writeText "portal-style.css" ''
    :root {
      color-scheme: dark;
      --bg-dim: ${p.bg_dim};
      --bg0: ${p.bg0};
      --bg1: ${p.bg1};
      --bg2: ${bg2Color};
      --bg-hover: ${p.bg_statusline2};
      --bg3: ${p.bg3};
      --bg5: ${p.bg5};
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
      --border: ${p.bg3};
      --border-strong: ${p.bg5};
      --border-hover: ${p.accent};
      --card-shadow: 0 8px 22px rgba(0, 0, 0, 0.28);
      --font-sans: "Inter", "Noto Sans", "Noto Sans CJK JP", system-ui, -apple-system, sans-serif;
      --font-mono: "Fira Code Nerd Font Mono", "Fira Code", ui-monospace, monospace;
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }

    body {
      min-height: 100vh;
      background-color: var(--bg0);
      color: var(--fg0);
      font-family: var(--font-sans);
      line-height: 1.5;
      padding: 2rem 1.25rem 3rem;
    }

    .shell {
      max-width: 1120px;
      margin: 0 auto;
      display: flex;
      flex-direction: column;
      gap: 1.65rem;
    }

    .topbar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 1rem;
      padding: 1.15rem 1.45rem;
      background: var(--bg1);
      border: 1px solid var(--border);
      border-top: 2px solid var(--accent);
      border-radius: 13px;
      box-shadow: var(--card-shadow);
    }

    .brand {
      display: flex;
      align-items: center;
      gap: 1rem;
    }

    .brand-logo {
      width: 48px;
      height: 48px;
      display: block;
      flex-shrink: 0;
    }

    .brand-title {
      font-size: 1.38rem;
      font-weight: 700;
      letter-spacing: -0.02em;
      color: var(--fg0);
    }

    .brand-subtitle {
      font-size: 0.82rem;
      color: var(--grey2);
      font-family: var(--font-mono);
    }

    .topbar-actions {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.55rem;
    }

    .pill {
      display: inline-flex;
      align-items: center;
      gap: 0.42rem;
      font-size: 0.75rem;
      font-weight: 600;
      font-family: var(--font-mono);
      padding: 0.28rem 0.65rem;
      border-radius: 999px;
      background: var(--bg0);
      color: var(--grey2);
      border: 1px solid var(--border);
      white-space: nowrap;
    }

    .pill[data-secure="true"] {
      color: var(--aqua);
      background: ${bgVisualBlue};
      border-color: ${rgba p.aqua "0.45"};
    }

    .pill[data-tone="ok"] {
      color: var(--green);
      background: ${bgVisualGreen};
      border-color: ${rgba p.green "0.45"};
    }

    .pill[data-tone="info"] {
      color: var(--blue);
      background: ${bgVisualBlue};
      border-color: ${rgba p.blue "0.45"};
    }

    .pill[data-tone="active"] {
      color: var(--purple);
      background: ${bgVisualPurple};
      border-color: ${rgba p.purple "0.45"};
    }

    .pill[data-tone="scheduled"],
    .pill[data-tone="warn"] {
      color: var(--yellow);
      background: ${p.bg_visual_yellow};
      border-color: ${rgba p.yellow "0.45"};
    }

    .pill[data-tone="crit"] {
      color: var(--red);
      background: ${p.bg_visual_red};
      border-color: ${rgba p.red "0.50"};
    }

    .dot {
      width: 7px;
      height: 7px;
      border-radius: 50%;
      background: currentColor;
      flex-shrink: 0;
    }

    .btn {
      background: var(--bg0);
      color: var(--fg0);
      border: 1px solid var(--border-strong);
      border-radius: 8px;
      padding: 0.34rem 0.8rem;
      font-size: 0.78rem;
      font-weight: 600;
      font-family: var(--font-sans);
      cursor: pointer;
      transition: border-color 140ms ease, background 140ms ease, color 140ms ease;
    }

    .btn:hover {
      background: var(--bg-hover);
      border-color: var(--border-hover);
      color: var(--accent);
    }

    .vitals-grid {
      position: relative;
      z-index: 20;
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 1rem;
    }

    @media (max-width: 980px) {
      .vitals-grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }

    @media (max-width: 560px) {
      .vitals-grid {
        grid-template-columns: 1fr;
      }
    }

    .vital-card {
      position: relative;
      background: var(--bg1);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 1.05rem 1.2rem;
      display: flex;
      flex-direction: column;
      gap: 0.45rem;
      box-shadow: var(--card-shadow);
      transition: border-color 140ms ease;
    }

    .vital-card:has(.nightly-details[open]) {
      z-index: 30;
      border-color: var(--border-strong);
    }

    .vital-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.5rem;
      min-height: 1.85rem;
    }

    .vital-label {
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.07em;
      color: var(--grey2);
      font-weight: 700;
    }

    .vital-primary {
      font-size: 1.28rem;
      font-weight: 700;
      font-family: var(--font-mono);
      font-variant-numeric: tabular-nums;
      color: var(--fg0);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .vital-denom {
      font-size: 0.84rem;
      font-weight: 500;
      color: var(--grey1);
    }

    .vital-secondary {
      font-size: 0.77rem;
      color: var(--grey2);
      font-variant-numeric: tabular-nums;
    }

    .bar-track {
      height: 7px;
      width: 100%;
      background: var(--bg-dim);
      border: 1px solid var(--border);
      border-radius: 999px;
      overflow: hidden;
      margin-top: auto;
      margin-bottom: 0.2rem;
    }

    .bar-fill {
      height: 100%;
      width: 0%;
      border-radius: 999px;
      background: var(--green);
      transition: width 260ms ease;
    }

    #cpu-bar {
      background: var(--green);
    }

    #mem-bar {
      background: var(--blue);
    }

    #disk-bar {
      background: var(--yellow);
    }

    .bar-fill[data-tone="warn"] {
      background: var(--orange) !important;
    }

    .bar-fill[data-tone="crit"] {
      background: var(--red) !important;
    }

    .nightly-details {
      margin-top: auto;
      padding-top: 0.15rem;
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
      display: none;
    }

    .nightly-details[open] .nightly-summary-list {
      position: absolute;
      top: calc(100% + 0.45rem);
      left: -1px;
      right: -1px;
      z-index: 30;
      margin: 0;
      padding: 0.75rem 1rem 0.75rem 1.85rem;
      background: var(--bg2);
      border: 1px solid var(--border-strong);
      border-radius: 12px;
      box-shadow: 0 14px 32px rgba(0, 0, 0, 0.52);
      color: var(--fg1);
      font-family: var(--font-mono);
      font-size: 0.73rem;
      display: flex;
      flex-direction: column;
      gap: 0.24rem;
    }

    @media (max-width: 560px) {
      .nightly-details[open] .nightly-summary-list {
        position: static;
        margin-top: 0.55rem;
      }
    }

    .services-root {
      display: flex;
      flex-direction: column;
      gap: 1.5rem;
    }

    .category-section {
      display: flex;
      flex-direction: column;
      gap: 0.8rem;
    }

    .category-title {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      font-size: 0.8rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.09em;
      color: var(--yellow);
    }

    .category-title::after {
      content: "";
      flex: 1;
      height: 1px;
      background: var(--border);
    }

    .cards-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 1rem;
    }

    @media (max-width: 760px) {
      .cards-grid {
        grid-template-columns: 1fr;
      }
    }

    .service-card {
      display: flex;
      flex-direction: column;
      gap: 0.65rem;
      padding: 1.2rem 1.35rem;
      background: var(--bg1);
      border: 1px solid var(--border);
      border-radius: 13px;
      box-shadow: var(--card-shadow);
      text-decoration: none;
      color: inherit;
      transition: transform 140ms ease, border-color 140ms ease, background 140ms ease;
    }

    a.service-card:hover {
      transform: translateY(-2px);
      background: var(--bg-hover);
      border-color: var(--border-hover);
    }

    .service-card--internal {
      border-style: dashed;
      border-color: var(--border-strong);
    }

    .card-top {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.6rem;
    }

    .card-icon {
      width: 42px;
      height: 42px;
      border-radius: 10px;
      background: var(--bg0);
      border: 1px solid var(--border);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
    }

    .card-icon-img {
      width: 24px;
      height: 24px;
      display: block;
    }

    .card-badges {
      display: flex;
      flex-wrap: wrap;
      gap: 0.4rem;
      justify-content: flex-end;
    }

    .card-title {
      font-size: 1.08rem;
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
      padding-top: 0.65rem;
      border-top: 1px solid var(--border);
      display: flex;
      align-items: center;
      justify-content: space-between;
      font-family: var(--font-mono);
      font-size: 0.77rem;
      color: var(--aqua);
    }

    a.service-card:hover .card-target {
      color: var(--yellow);
    }

    .card-arrow {
      font-size: 0.95rem;
      color: var(--orange);
    }

    .card-hint {
      margin-top: 0.25rem;
      padding: 0.45rem 0.65rem;
      background: var(--bg-dim);
      border: 1px solid var(--border);
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.6rem;
    }

    .card-hint-code {
      font-family: var(--font-mono);
      font-size: 0.74rem;
      color: var(--fg0);
      overflow-x: auto;
      white-space: nowrap;
    }

    .copy-btn {
      background: var(--bg1);
      color: var(--fg0);
      border: 1px solid var(--border-strong);
      border-radius: 6px;
      padding: 0.22rem 0.55rem;
      font-size: 0.72rem;
      font-weight: 600;
      font-family: var(--font-sans);
      cursor: pointer;
      flex-shrink: 0;
      transition: border-color 140ms ease, color 140ms ease, background 140ms ease;
    }

    .copy-btn:hover {
      background: var(--bg-hover);
      border-color: var(--border-hover);
      color: var(--accent);
    }

    .footer-bar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 0.8rem;
      padding: 0.95rem 1.35rem;
      background: var(--bg1);
      border: 1px solid var(--border);
      border-radius: 12px;
      box-shadow: var(--card-shadow);
    }

    .footer-label {
      font-size: 0.76rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--grey2);
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
      gap: 0.4rem;
      padding: 0.25rem 0.65rem;
      border-radius: 999px;
      font-family: var(--font-mono);
      font-size: 0.74rem;
      background: var(--bg0);
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
      background: ${p.bg_visual_red};
      border-color: ${rgba p.red "0.50"};
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
      <meta name="color-scheme" content="dark">
      <meta name="darkreader-lock">
      <title>${config.networking.hostName} · Overview</title>
      <link rel="icon" type="image/svg+xml" href="/favicon.svg">
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
    mkdir -p "$out/icons"
    ln -s ${indexHtml} "$out/index.html"
    ln -s ${styleCss} "$out/style.css"
    ln -s ${./scripts/portal-app.js} "$out/app.js"
    ln -s ${portalConfigJson} "$out/portal-config.json"
    ln -s ${../../assets/icon.svg} "$out/icon.svg"
    ln -s ${faviconSvg} "$out/favicon.svg"
    ln -s ${iconSvgs.music} "$out/icons/music.svg"
    ln -s ${iconSvgs.sync} "$out/icons/sync.svg"
    ln -s ${iconSvgs.package} "$out/icons/package.svg"
    ln -s ${iconSvgs.code} "$out/icons/code.svg"
    ln -s ${iconSvgs.globe} "$out/icons/globe.svg"
    ln -s ${iconSvgs.tasks} "$out/icons/tasks.svg"
    ln -s ${iconSvgs.calendar} "$out/icons/calendar.svg"
    ln -s ${iconSvgs.chat} "$out/icons/chat.svg"
    ln -s ${iconSvgs.bot} "$out/icons/bot.svg"
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
        description = "Built-in icon identifier (`music`, `sync`, `package`, `code`, `globe`, `tasks`, `calendar`).";
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

      subdomain = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        example = "music";
        description = ''
          Dedicated Nginx virtual host prefix (`<subdomain>.<domainSuffix>`)
          reverse-proxying `/` to `proxyPass` with the portal TLS certificate.
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
        description = "Optional upstream URL for Nginx `proxy_pass` at `location` or `subdomain`.";
      };

      proxyWebsockets = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Forward WebSocket upgrade headers when `proxyPass` is set.";
      };

      extraProxyConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Additional Nginx directives appended to the proxied location block.";
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

    domainSuffix = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "${config.networking.hostName}.internal";
      defaultText = lib.literalExpression ''"<hostName>.internal"'';
      description = "Base domain suffix appended to `services.<name>.subdomain` virtual hosts.";
    };

    extraLocations = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional Nginx location blocks attached to the default portal virtual host.";
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
      custom.services.portal = {
        services = {
          navidrome =
            let
              navCfg = config.custom.services.navidrome or { };
              navPort = navCfg.port or 4533;
              navProxied = (navCfg.reverseProxy.enable or false) && cfg.enable;
            in
            lib.mkIf (navCfg.enable or false) {
              title = lib.mkDefault "Navidrome";
              description = lib.mkDefault "Self-hosted music streaming server and Subsonic API";
              category = lib.mkDefault "Media & Sync";
              badge = lib.mkDefault (if navProxied then "HTTPS · Subsonic" else "TCP ${toString navPort}");
              icon = lib.mkDefault "music";
              subdomain = lib.mkIf navProxied (lib.mkDefault (navCfg.reverseProxy.subdomain or "music"));
              proxyPass = lib.mkIf navProxied (lib.mkDefault "http://127.0.0.1:${toString navPort}");
              extraProxyConfig = lib.mkIf navProxied (
                lib.mkDefault ''
                  proxy_buffering off;
                  client_max_body_size 32M;
                ''
              );
              port = lib.mkIf (!navProxied) (lib.mkDefault navPort);
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

          litellm =
            let
              aiCfg = config.custom.services.ai or { };
              litellmCfg = aiCfg.litellm or { };
              pStr = toString (litellmCfg.port or 4000);
            in
            lib.mkIf (litellmCfg.enable or false) {
              title = lib.mkDefault "LiteLLM Gateway";
              description = lib.mkDefault "Rotated Gemini 4 Hydrogen proxy bound to loopback";
              category = lib.mkDefault "Infrastructure";
              badge = lib.mkDefault "127.0.0.1:${pStr}";
              icon = lib.mkDefault "code";
              systemdUnit = lib.mkDefault "litellm.service";
              hintCommand = lib.mkDefault "ssh -N -L ${pStr}:127.0.0.1:${pStr} ${user}@{host}";
              order = lib.mkDefault 35;
            };
        };

        extraLocations =
          let
            navCfg = config.custom.services.navidrome or { };
            navPort = navCfg.port or 4533;
            enableMobileSubsonic =
              cfg.enable
              && (navCfg.enable or false)
              && (navCfg.reverseProxy.enable or false)
              && (navCfg.reverseProxy.mobileSubsonicPath or false);
          in
          lib.mkIf enableMobileSubsonic {
            "/music/rest/" = {
              proxyPass = "http://127.0.0.1:${toString navPort}/rest/";
              extraConfig = ''
                proxy_buffering off;
              '';
            };
            "/music/share/" = {
              proxyPass = "http://127.0.0.1:${toString navPort}/share/";
              extraConfig = ''
                proxy_buffering off;
              '';
            };
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
                lib.optional (s.subdomain != null) "subdomain"
                ++ lib.optional (s.location != null) "location"
                ++ lib.optional (s.port != null) "port"
                ++ lib.optional (s.url != null) "url";
            in
            (s.proxyPass != null -> (s.location != null || s.subdomain != null))
            && (s.subdomain != null -> (s.proxyPass != null && validSubdomain s.subdomain))
            && builtins.length targets <= 1
          ) (builtins.attrValues activeServices);
          message = "custom.services.portal.services: each entry may set at most one of subdomain, location, port, or url; subdomain must be a valid DNS label with proxyPass set.";
        }
        {
          assertion = builtins.length allSubdomains == builtins.length (lib.unique allSubdomains);
          message = "custom.services.portal.services: duplicate subdomain across active services.";
        }
        {
          assertion = lib.all (
            loc:
            let
              norm = lib.removePrefix "= " loc;
            in
            lib.hasPrefix "/" norm
            && !(lib.hasPrefix "/icons/" norm)
            && !(builtins.elem norm reservedLocations)
            && !(builtins.elem loc reservedLocations)
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

        virtualHosts = {
          ${cfg.serverName} = {
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
            // cfg.extraLocations
            // proxiedServiceLocations
            // proxiedProjectLocations;
          };
        }
        // subdomainVirtualHosts;
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
