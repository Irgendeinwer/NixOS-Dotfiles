{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.services.matrix;
  isContainer = config.boot.isContainer or false;
  portalCfg = config.custom.services.portal or { };
  portalEnabled = portalCfg.enable or false;
  portalTls = portalEnabled && (portalCfg.tls.enable or true);
  portalScheme = if portalTls then "https" else "http";
  portalDomainSuffix = portalCfg.domainSuffix or "${config.networking.hostName}.internal";
  publicBaseUrl = "${portalScheme}://${cfg.subdomain}.${portalDomainSuffix}";

  wellKnownClientJson = builtins.toJSON {
    "m.homeserver".base_url = publicBaseUrl;
  };

  matrixExtraLocations = {
    "= /.well-known/matrix/client".extraConfig = ''
      default_type application/json;
      add_header Access-Control-Allow-Origin "*" always;
      add_header Cache-Control "public, max-age=3600" always;
      return 200 '${wellKnownClientJson}';
    '';
  }
  // lib.optionalAttrs cfg.mobileMatrixPath {
    "/_matrix/" = {
      proxyPass = "http://127.0.0.1:${toString cfg.port}/_matrix/";
      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 64M;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_buffering off;
      '';
    };
  };
in
{
  options.custom.services.matrix = {
    enable = lib.mkEnableOption "private Continuwuity Matrix homeserver behind the portal proxy";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6167;
      description = "Loopback TCP port for Continuwuity (`127.0.0.1:<port>`).";
    };

    subdomain = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "matrix";
      description = "Subdomain prefix under `custom.services.portal.domainSuffix` for Matrix.";
    };

    serverName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = portalDomainSuffix;
      defaultText = lib.literalExpression ''portal.domainSuffix or "<hostName>.internal"'';
      description = "Matrix `server_name` suffix embedded in `@user:<serverName>` identifiers.";
    };

    allowRegistration = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow Matrix client registration (requires `registrationTokenFile` when
        enabled). Keep `false` and provision accounts via `conduwuit --execute`.
      '';
    };

    registrationTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional token file gating registration when `allowRegistration = true`.";
    };

    maxRequestSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 67108864;
      description = "Maximum Matrix request/upload payload size in bytes (default 64 MiB).";
    };

    mobileMatrixPath = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Also proxy `/_matrix/` on the default portal virtual host so mobile
        Element clients can connect over raw Tailscale IP (`https://<ip>`)
        without split-DNS or `/etc/hosts`.
      '';
    };
  };

  config = lib.mkMerge [
    {
      assertions = lib.optional (cfg.enable && cfg.allowRegistration) {
        assertion = cfg.registrationTokenFile != null;
        message = "custom.services.matrix: allowRegistration requires registrationTokenFile.";
      };

      custom.services.portal = {
        services.matrix = lib.mkIf (portalEnabled && cfg.enable) {
          title = lib.mkDefault "Matrix";
          description = lib.mkDefault "Private Continuwuity Matrix homeserver for Element & Hermes";
          category = lib.mkDefault "Productivity";
          badge = lib.mkDefault "HTTPS · Matrix";
          icon = lib.mkDefault "chat";
          subdomain = lib.mkDefault cfg.subdomain;
          proxyPass = lib.mkDefault "http://127.0.0.1:${toString cfg.port}";
          path = lib.mkDefault "/_matrix/client/versions";
          extraProxyConfig = lib.mkDefault ''
            client_max_body_size 64M;
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
            proxy_buffering off;
          '';
          systemdUnit = lib.mkDefault "continuwuity.service";
          order = lib.mkDefault 18;
        };

        extraLocations = lib.mkIf (portalEnabled && cfg.enable) matrixExtraLocations;
      };
    }

    (lib.mkIf cfg.enable {
      services.matrix-continuwuity = {
        enable = true;
        settings.global = {
          server_name = cfg.serverName;
          address = [ "127.0.0.1" ];
          port = [ cfg.port ];
          max_request_size = cfg.maxRequestSize;
          allow_registration = cfg.allowRegistration;
          registration_token_file = cfg.registrationTokenFile;
          allow_encryption = true;
          allow_federation = false;
          allow_announcements_check = false;
          trusted_servers = [ ];
          well_known.client = publicBaseUrl;
        };
      };

      # Upstream enables DynamicUser, PrivateUsers, and ProtectProc=invisible,
      # which fail inside systemd-nspawn containers with PrivateUsers=no.
      systemd.services.continuwuity.serviceConfig = lib.mkIf isContainer {
        DynamicUser = lib.mkForce false;
        PrivateUsers = lib.mkForce false;
        ProtectProc = lib.mkForce "default";
        ProtectHostname = lib.mkForce false;
        ProtectClock = lib.mkForce false;
      };

      # Keep admin CLI state readable/writable exclusively by the static user.
      environment.systemPackages = [ pkgs.jq ];
    })
  ];
}
