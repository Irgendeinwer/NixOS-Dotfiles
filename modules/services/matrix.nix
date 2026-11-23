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
  portalMatrixEnabled =
    portalEnabled && (config.custom.services.portal.services.matrix.enable or true);
  portalTls = portalEnabled && (portalCfg.tls.enable or true);
  portalScheme = if portalTls then "https" else "http";
  portalDomainSuffix = portalCfg.domainSuffix or "${config.networking.hostName}.internal";
  matrixHost = "${cfg.subdomain}.${portalDomainSuffix}";
  publicBaseUrl = "${portalScheme}://${matrixHost}";

  corsAllowHeaders = lib.concatStringsSep ", " [
    "Origin"
    "X-Requested-With"
    "Content-Type"
    "Accept"
    "Authorization"
    "Date"
    "Cache-Control"
    "Pragma"
    "If-None-Match"
  ];

  wellKnownClientJson = builtins.toJSON {
    "m.homeserver".base_url = publicBaseUrl;
  };

  wellKnownDynamicJson = ''{"m.homeserver":{"base_url":"$junix_matrix_base_url"}}'';
  wellKnownBody = if cfg.mobileMatrixPath then wellKnownDynamicJson else wellKnownClientJson;

  wellKnownLocation = {
    extraConfig = ''
      default_type application/json;
      add_header Access-Control-Allow-Origin "*" always;
      add_header Access-Control-Allow-Methods "GET, HEAD, OPTIONS" always;
      add_header Access-Control-Allow-Headers "${corsAllowHeaders}" always;
      add_header Access-Control-Allow-Private-Network "true" always;
      add_header Cache-Control "public, max-age=3600" always;
      ${lib.optionalString cfg.mobileMatrixPath ''add_header Vary "Host" always;''}
      return 200 '${wellKnownBody}';
    '';
  };

  matrixProxyConfig = ''
    client_max_body_size ${toString cfg.maxRequestSize};
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;
    proxy_buffering off;
    proxy_hide_header Access-Control-Allow-Origin;
    proxy_hide_header Access-Control-Allow-Methods;
    proxy_hide_header Access-Control-Allow-Headers;
    proxy_hide_header Access-Control-Allow-Private-Network;
    add_header Access-Control-Allow-Origin "*" always;
    add_header Access-Control-Allow-Methods "GET, HEAD, POST, PUT, DELETE, PATCH, OPTIONS" always;
    add_header Access-Control-Allow-Headers "${corsAllowHeaders}" always;
    add_header Access-Control-Allow-Private-Network "true" always;
  '';

  matrixApiLocation = {
    proxyPass = "http://127.0.0.1:${toString cfg.port}";
    proxyWebsockets = true;
    extraConfig = matrixProxyConfig;
  };

  matrixExtraLocations = {
    "= /.well-known/matrix/client" = wellKnownLocation;
  }
  // lib.optionalAttrs cfg.mobileMatrixPath {
    "/_matrix/" = matrixApiLocation;
  };

  cinnyStaticConf = {
    defaultHomeserver = 0;
    homeserverList = [ matrixHost ];
    inherit (cfg.webClient) allowCustomHomeservers;
    featuredCommunities = {
      openAsDefault = false;
      spaces = [ ];
      rooms = [ ];
      servers = [ ];
    };
    hashRouter = {
      enabled = false;
      basename = "/";
    };
  };

  defaultCinnyPackage = pkgs.cinny.override {
    conf = cinnyStaticConf;
  };

  cinnyDynamicConfigJson =
    ''{"defaultHomeserver":0,"homeserverList":$junix_cinny_homeserver_list,''
    + ''"allowCustomHomeservers":${lib.boolToString cfg.webClient.allowCustomHomeservers},''
    + ''"featuredCommunities":{"openAsDefault":false,"spaces":[],"rooms":[],"servers":[]},''
    + ''"hashRouter":{"enabled":false,"basename":"/"}}'';

  mobileHttpsPort = cfg.webClient.mobileHttpsPort;
  mobileHttpsActive =
    portalMatrixEnabled
    && portalTls
    && cfg.enable
    && cfg.webClient.enable
    && cfg.mobileMatrixPath
    && mobileHttpsPort != null;
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
        Matrix clients can connect over raw Tailscale IP (`https://<ip>`)
        without split-DNS or `/etc/hosts`.
      '';
    };

    webClient = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Serve the self-hosted Cinny Matrix web client at `/` on
          `https://<subdomain>.<domainSuffix>/` alongside `/_matrix/` and
          `/.well-known/matrix/client` (same-origin, zero extra daemon RAM).
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = defaultCinnyPackage;
        defaultText = lib.literalExpression "pkgs.cinny.override { conf = ...; }";
        description = "Static Cinny Matrix web client bundle served on the Matrix virtual host.";
      };

      allowCustomHomeservers = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Allow entering custom homeservers in Cinny's login server picker.";
      };

      mobileHttpsPort = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = 8448;
        description = ''
          Additional HTTPS port on the Matrix virtual host (`default_server`)
          so mobile browsers over raw Tailscale IP (`https://<ip>:8448/`) can
          install and use the self-hosted Cinny PWA without split-DNS. Set to
          `null` to disable.
        '';
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions =
        lib.optional (cfg.enable && cfg.allowRegistration) {
          assertion = cfg.registrationTokenFile != null;
          message = "custom.services.matrix: allowRegistration requires registrationTokenFile.";
        }
        ++ lib.optional (cfg.enable && cfg.webClient.enable && mobileHttpsPort != null) {
          assertion =
            !(builtins.elem mobileHttpsPort [
              80
              443
            ]);
          message = "custom.services.matrix.webClient: mobileHttpsPort must not collide with ports 80 or 443.";
        };

      custom.services.portal = {
        services.matrix = lib.mkIf (portalEnabled && cfg.enable) (
          {
            title = lib.mkDefault "Matrix";
            category = lib.mkDefault "Productivity";
            icon = lib.mkDefault "chat";
            subdomain = lib.mkDefault cfg.subdomain;
            systemdUnit = lib.mkDefault "continuwuity.service";
            order = lib.mkDefault 18;
          }
          // (
            if cfg.webClient.enable then
              {
                description = lib.mkDefault "Self-hosted Cinny Matrix client & Continuwuity homeserver";
                badge = lib.mkDefault "HTTPS · Cinny";
                webRoot = lib.mkDefault cfg.webClient.package;
                path = lib.mkDefault "/";
              }
            else
              {
                description = lib.mkDefault "Private Continuwuity Matrix homeserver for Element & Hermes";
                badge = lib.mkDefault "HTTPS · Matrix";
                proxyPass = lib.mkDefault "http://127.0.0.1:${toString cfg.port}";
                path = lib.mkDefault "/_matrix/client/versions";
                extraProxyConfig = lib.mkDefault matrixProxyConfig;
              }
          )
        );

        extraLocations = lib.mkIf (portalEnabled && cfg.enable) matrixExtraLocations;
      };
    }

    (lib.mkIf cfg.enable {
      networking.firewall.allowedTCPPorts = lib.mkIf (
        mobileHttpsActive && (portalCfg.openFirewall or false)
      ) [ mobileHttpsPort ];

      services.nginx = lib.mkIf portalEnabled {
        appendHttpConfig =
          let
            domainPattern = lib.replaceStrings [ "." ] [ "[.]" ] portalDomainSuffix;
            subPattern = lib.replaceStrings [ "." ] [ "[.]" ] matrixHost;
          in
          lib.mkIf cfg.mobileMatrixPath (
            ''
              map $http_host $junix_matrix_base_url {
                default "${publicBaseUrl}";
                "~*^${domainPattern}(?::[0-9]+)?$" "${publicBaseUrl}";
                "~*^${subPattern}(?::[0-9]+)?$" "${publicBaseUrl}";
                "~^(?<junix_matrix_req_host>[][A-Za-z0-9._:-]+)$" "${portalScheme}://$junix_matrix_req_host";
              }
            ''
            + lib.optionalString cfg.webClient.enable ''
              map $http_host $junix_cinny_homeserver_list {
                default '["${matrixHost}"]';
                "~*^${domainPattern}(?::[0-9]+)?$" '["${matrixHost}"]';
                "~*^${subPattern}(?::[0-9]+)?$" '["${matrixHost}"]';
                "~^(?<junix_cinny_req_host>[][A-Za-z0-9._:-]+)$" '["$junix_cinny_req_host","${matrixHost}"]';
              }
            ''
          );

        virtualHosts.${matrixHost} = lib.mkIf portalMatrixEnabled {
          listen = lib.mkIf mobileHttpsActive [
            {
              addr = "0.0.0.0";
              port = 80;
              ssl = false;
            }
            {
              addr = "[::0]";
              port = 80;
              ssl = false;
            }
            {
              addr = "0.0.0.0";
              port = 443;
              ssl = true;
            }
            {
              addr = "[::0]";
              port = 443;
              ssl = true;
            }
            {
              addr = "0.0.0.0";
              port = mobileHttpsPort;
              ssl = true;
              extraParameters = [ "default_server" ];
            }
            {
              addr = "[::0]";
              port = mobileHttpsPort;
              ssl = true;
              extraParameters = [ "default_server" ];
            }
          ];

          locations = {
            "= /.well-known/matrix/client" = wellKnownLocation;
          }
          // lib.optionalAttrs cfg.webClient.enable {
            "/_matrix/" = matrixApiLocation;

            "= /config.json".extraConfig =
              if cfg.mobileMatrixPath then
                ''
                  default_type application/json;
                  add_header Cache-Control "no-cache" always;
                  add_header X-Content-Type-Options "nosniff" always;
                  add_header Vary "Host" always;
                  return 200 '${cinnyDynamicConfigJson}';
                ''
              else
                ''
                  add_header Cache-Control "no-cache" always;
                  add_header X-Content-Type-Options "nosniff" always;
                '';

            "= /index.html".extraConfig = ''
              add_header Cache-Control "no-cache" always;
              add_header X-Content-Type-Options "nosniff" always;
              add_header X-Frame-Options "SAMEORIGIN" always;
              add_header Referrer-Policy "same-origin" always;
            '';

            "= /sw.js" = {
              tryFiles = "/sw.js =404";
              extraConfig = ''
                add_header Cache-Control "no-cache" always;
                add_header X-Content-Type-Options "nosniff" always;
              '';
            };

            "/assets/" = {
              tryFiles = "$uri =404";
              extraConfig = ''
                add_header Cache-Control "public, max-age=31536000, immutable" always;
                add_header X-Content-Type-Options "nosniff" always;
              '';
            };

            "/public/" = {
              tryFiles = "$uri =404";
              extraConfig = ''
                add_header X-Content-Type-Options "nosniff" always;
              '';
            };
          };
        };
      };

      services.matrix-continuwuity = {
        enable = true;
        settings.global = {
          server_name = cfg.serverName;
          address = [ "127.0.0.1" ];
          port = [ cfg.port ];
          max_request_size = cfg.maxRequestSize;
          allow_registration = cfg.allowRegistration;
          allow_encryption = true;
          allow_federation = false;
          allow_announcements_check = false;
          trusted_servers = [ ];
          well_known.client = publicBaseUrl;
        }
        // lib.optionalAttrs (cfg.registrationTokenFile != null) {
          registration_token_file = cfg.registrationTokenFile;
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
