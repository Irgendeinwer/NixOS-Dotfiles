{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.planner;
  portalCfg = config.custom.services.portal or { };
  portalEnabled = portalCfg.enable or false;
  portalTls = portalEnabled && (portalCfg.tls.enable or true);
  portalDomainSuffix = portalCfg.domainSuffix or "${config.networking.hostName}.internal";

  sopsFile = ../../secrets + "/${config.networking.hostName}.yaml";
  useSopsVikunja = cfg.vikunja.enable && cfg.vikunja.environmentFile == null;
  useSopsRadicale = cfg.radicale.enable && cfg.radicale.htpasswdFile == null;

  vikunjaEnvPath =
    if cfg.vikunja.environmentFile != null then
      "${cfg.vikunja.environmentFile}"
    else if useSopsVikunja then
      config.sops.secrets.vikunja_env.path
    else
      "/run/secrets/vikunja_env";

  radicaleHtpasswdPath =
    if cfg.radicale.htpasswdFile != null then
      "${cfg.radicale.htpasswdFile}"
    else if useSopsRadicale then
      config.sops.secrets.radicale_htpasswd.path
    else
      "/run/secrets/radicale_htpasswd";
in
{
  options.custom.services.planner = {
    enable = lib.mkEnableOption "Vikunja task server and Radicale CalDAV calendar server";

    vikunja = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        defaultText = lib.literalExpression "config.custom.services.planner.enable";
        description = "Run Vikunja on loopback and expose it over the portal reverse proxy.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 3456;
        description = "Loopback TCP port for Vikunja (`127.0.0.1:<port>`).";
      };

      subdomain = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "tasks";
        description = "Subdomain prefix under `custom.services.portal.domainSuffix` for Vikunja.";
      };

      enableRegistration = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Allow open web self-registration in Vikunja. Keep disabled and create
          users explicitly via `sudo -Hu vikunja vikunja user create`.
        '';
      };

      timeZone = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = if config.time.timeZone != null then config.time.timeZone else "Europe/Berlin";
        defaultText = lib.literalExpression ''config.time.timeZone or "Europe/Berlin"'';
        description = "Default server timezone configured in Vikunja.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Environment file setting `VIKUNJA_SERVICE_SECRET`; `null` reads
          `vikunja_env` from the host's sops secrets file.
        '';
      };
    };

    radicale = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        defaultText = lib.literalExpression "config.custom.services.planner.enable";
        description = "Run Radicale CalDAV on loopback and expose it over the portal reverse proxy.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5232;
        description = "Loopback TCP port for Radicale (`127.0.0.1:<port>`).";
      };

      subdomain = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "cal";
        description = "Subdomain prefix under `custom.services.portal.domainSuffix` for Radicale.";
      };

      mobileCaldavPath = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Also expose Radicale under `/cal/` (`X-Script-Name: /cal`) on the
          default portal virtual host so mobile DAVx5 clients can sync via raw
          Tailscale IP (`https://<ip>/cal/`) without `/etc/hosts`.
        '';
      };

      htpasswdFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Bcrypt htpasswd file for Radicale authentication; `null` reads
          `radicale_htpasswd` from the host's sops secrets file.
        '';
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = lib.optional (cfg.vikunja.enable && cfg.radicale.enable) {
        assertion = cfg.vikunja.port != cfg.radicale.port;
        message = "custom.services.planner: vikunja.port and radicale.port must be distinct.";
      };

      custom.services.portal = {
        services = {
          vikunja = lib.mkIf (portalEnabled && cfg.vikunja.enable) {
            title = lib.mkDefault "Vikunja";
            description = lib.mkDefault "Projects, quick to-dos, subtasks, and step planning API";
            category = lib.mkDefault "Productivity";
            badge = lib.mkDefault "HTTPS · Tasks";
            icon = lib.mkDefault "tasks";
            subdomain = lib.mkDefault cfg.vikunja.subdomain;
            proxyPass = lib.mkDefault "http://127.0.0.1:${toString cfg.vikunja.port}";
            extraProxyConfig = lib.mkDefault ''
              client_max_body_size 64M;
            '';
            systemdUnit = lib.mkDefault "vikunja.service";
            order = lib.mkDefault 15;
          };

          radicale = lib.mkIf (portalEnabled && cfg.radicale.enable) {
            title = lib.mkDefault "Radicale";
            description = lib.mkDefault "CalDAV appointments, schedules, and mobile DAVx5 sync";
            category = lib.mkDefault "Productivity";
            badge = lib.mkDefault "HTTPS · CalDAV";
            icon = lib.mkDefault "calendar";
            subdomain = lib.mkDefault cfg.radicale.subdomain;
            proxyPass = lib.mkDefault "http://127.0.0.1:${toString cfg.radicale.port}";
            path = lib.mkDefault "/.web/";
            systemdUnit = lib.mkDefault "radicale.service";
            order = lib.mkDefault 16;
          };
        };

        extraLocations = lib.mkIf (portalEnabled && cfg.radicale.enable && cfg.radicale.mobileCaldavPath) {
          "= /cal".return = "308 /cal/";
          "/cal/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.radicale.port}/";
            extraConfig = ''
              proxy_set_header X-Script-Name /cal;
            '';
          };
        };
      };
    }

    (lib.mkIf cfg.vikunja.enable {
      users.groups.vikunja = { };
      users.users.vikunja = {
        isSystemUser = true;
        group = "vikunja";
        home = "/var/lib/vikunja";
      };

      sops.secrets = lib.mkIf useSopsVikunja {
        vikunja_env = {
          inherit sopsFile;
          key = "vikunja_env";
          mode = "0400";
          restartUnits = [ "vikunja.service" ];
        };
      };

      services.vikunja = {
        enable = true;
        address = "127.0.0.1";
        port = cfg.vikunja.port;
        frontendScheme = if portalTls then "https" else "http";
        frontendHostname = "${cfg.vikunja.subdomain}.${portalDomainSuffix}";
        environmentFiles = [ vikunjaEnvPath ];
        settings.service = {
          enablelinksharing = false;
          enabletaskattachments = true;
          enableregistration = cfg.vikunja.enableRegistration;
          maxitemsperpage = 200;
          timezone = cfg.vikunja.timeZone;
        };
      };

      # Upstream sets DynamicUser = true, which fails inside systemd-nspawn
      # containers without unprivileged user namespaces.
      systemd.services.vikunja.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "vikunja";
        Group = "vikunja";
        StateDirectory = "vikunja";
        StateDirectoryMode = "0750";
        WorkingDirectory = "/var/lib/vikunja";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateUsers = lib.mkForce (!config.boot.isContainer);
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    })

    (lib.mkIf cfg.radicale.enable {
      sops.secrets = lib.mkIf useSopsRadicale {
        radicale_htpasswd = {
          inherit sopsFile;
          key = "radicale_htpasswd";
          owner = config.services.radicale.user;
          group = config.services.radicale.group;
          mode = "0400";
          restartUnits = [ "radicale.service" ];
        };
      };

      services.radicale = {
        enable = true;
        settings = {
          server.hosts = [ "127.0.0.1:${toString cfg.radicale.port}" ];
          auth = {
            type = "htpasswd";
            htpasswd_filename = radicaleHtpasswdPath;
            htpasswd_encryption = "bcrypt";
          };
          storage.filesystem_folder = "/var/lib/radicale/collections";
          web.type = "internal";
        };
        rights = {
          root = {
            user = ".+";
            collection = "";
            permissions = "R";
          };
          principal = {
            user = ".+";
            collection = "{user}";
            permissions = "RW";
          };
          calendars = {
            user = ".+";
            collection = "{user}/[^/]+";
            permissions = "rw";
          };
        };
      };

      systemd.services.radicale.serviceConfig = {
        PrivateUsers = lib.mkForce (!config.boot.isContainer);
      };
    })
  ];
}
