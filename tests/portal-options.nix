{
  nixpkgs,
  pkgs,
  self,
  sopsModule,
}:
let
  inherit (nixpkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;

  dummyCa = pkgs.writeText "dummy-junix-ca.pem" "TEST-CA\n";
  dummyCert = pkgs.writeText "dummy-portal-cert.pem" "TEST-CERT\n";
  dummyKey = pkgs.writeText "dummy-portal-key.pem" "TEST-KEY\n";

  evalPortal =
    extraConfig:
    (lib.nixosSystem {
      inherit system;
      modules = [
        sopsModule
        {
          options.custom.user = lib.mkOption {
            type = lib.types.str;
            default = "irgendeinwer";
          };
        }
        ../modules/nixos/pki.nix
        ../modules/services/syncthing.nix
        ../modules/services/navidrome.nix
        ../modules/services/portal.nix
        {
          networking.hostName = "junixsrv";
          system.stateVersion = "26.11";
        }
        extraConfig
      ];
    }).config;

  disabled = evalPortal { };

  httpsSops = evalPortal {
    boot.isContainer = true;
    custom.system.security.localCa.certificateFile = dummyCa;
    custom.services = {
      syncthing.enable = true;
      navidrome.enable = true;
      portal = {
        enable = true;
        projects.study-tracker = {
          title = "Study Tracker";
          description = "Exam & homework planner";
          port = 18090;
          execStart = "/bin/true";
          environment.APP_ENV = "production";
        };
      };
    };
  };

  httpOnly = evalPortal {
    custom.system.security.localCa = {
      enable = false;
      certificateFile = dummyCa;
    };
    custom.services.portal = {
      enable = true;
      tls.enable = false;
      projects.raw-uri = {
        port = 18091;
        stripPrefix = false;
      };
    };
  };

  customTls = evalPortal {
    custom.services.portal = {
      enable = true;
      openFirewall = false;
      tls = {
        enable = true;
        certificateFile = dummyCert;
        keyFile = dummyKey;
      };
    };
  };

  halfTls = evalPortal {
    custom.services.portal = {
      enable = true;
      tls.certificateFile = dummyCert;
    };
  };

  reservedCollision = evalPortal {
    custom.services.portal = {
      enable = true;
      projects.bad = {
        port = 18092;
        location = "/api/status";
      };
    };
  };

  portCollision = evalPortal {
    custom.services.portal = {
      enable = true;
      projects.bad = {
        port = 18080;
      };
    };
  };

  multiTargetService = evalPortal {
    custom.services.portal = {
      enable = true;
      services.ambiguous = {
        title = "Ambiguous";
        port = 9000;
        url = "https://example.invalid";
      };
    };
  };

  stripPrefixNoSlash = evalPortal {
    custom.services.portal = {
      enable = true;
      projects.noslash = {
        port = 18093;
        location = "/noslash";
        stripPrefix = true;
      };
    };
  };

  unmanagedPortDup = evalPortal {
    custom.services.portal = {
      enable = true;
      projects = {
        first.port = 18094;
        second.port = 18094;
      };
    };
  };

  duplicateSubdomain = evalPortal {
    custom.services.portal = {
      enable = true;
      services = {
        one = {
          title = "One";
          subdomain = "dup";
          proxyPass = "http://127.0.0.1:19001";
        };
        two = {
          title = "Two";
          subdomain = "dup";
          proxyPass = "http://127.0.0.1:19002";
        };
      };
    };
  };

  subdomainWithoutProxy = evalPortal {
    custom.services.portal = {
      enable = true;
      services.badsub = {
        title = "BadSub";
        subdomain = "bad";
      };
    };
  };

  hasFailedAssertion =
    prefix: cfg: lib.any (a: !a.assertion && lib.hasPrefix prefix a.message) cfg.assertions;

  vhost = httpsSops.services.nginx.virtualHosts.junixsrv;
  musicVhost = httpsSops.services.nginx.virtualHosts."music.junixsrv.internal";
  studySvc = httpsSops.systemd.services.portal-project-study-tracker;
  httpVhost = httpOnly.services.nginx.virtualHosts.junixsrv;
  serverHost = self.nixosConfigurations.junixsrv.config;
  serverVhost = serverHost.services.nginx.virtualHosts.junixsrv;
in
assert !disabled.services.nginx.enable;
assert !(builtins.hasAttr "junix-portal-status" disabled.systemd.services);
assert !(builtins.hasAttr "portal_tls_cert" disabled.sops.secrets);
assert httpsSops.services.nginx.enable;
assert builtins.elem dummyCa httpsSops.security.pki.certificateFiles;
assert builtins.elem 80 httpsSops.networking.firewall.allowedTCPPorts;
assert builtins.elem 443 httpsSops.networking.firewall.allowedTCPPorts;
assert vhost.default && vhost.forceSSL;
assert builtins.elem "junixsrv.local" vhost.serverAliases;
assert builtins.elem "junixsrv.internal" vhost.serverAliases;
assert builtins.hasAttr "portal_tls_cert" httpsSops.sops.secrets;
assert builtins.hasAttr "portal_tls_key" httpsSops.sops.secrets;
assert httpsSops.sops.secrets.portal_tls_cert.mode == "0400";
assert builtins.elem "nginx.service" httpsSops.sops.secrets.portal_tls_cert.reloadUnits;
assert vhost.locations."= /api/status".proxyPass == "http://127.0.0.1:18080/api/status";
assert vhost.locations."/study-tracker/".proxyPass == "http://127.0.0.1:18090/";
assert vhost.locations."/music/rest/".proxyPass == "http://127.0.0.1:4533/rest/";
assert vhost.locations."/music/share/".proxyPass == "http://127.0.0.1:4533/share/";
assert lib.hasInfix "Content-Security-Policy" vhost.locations."/".extraConfig;
assert !(lib.hasInfix "Content-Security-Policy" vhost.extraConfig);
assert httpsSops.custom.services.portal.services.navidrome.port == null;
assert httpsSops.custom.services.portal.services.navidrome.subdomain == "music";
assert httpsSops.custom.services.portal.services.navidrome.proxyPass == "http://127.0.0.1:4533";
assert httpsSops.custom.services.portal.services.navidrome.path == "/app/";
assert musicVhost.forceSSL;
assert musicVhost.locations."/".proxyPass == "http://127.0.0.1:4533";
# Syncthing stays internal-only (unexposed on Nginx and direct ports).
assert httpsSops.custom.services.portal.services.syncthing.port == null;
assert httpsSops.custom.services.portal.services.syncthing.location == null;
assert httpsSops.custom.services.portal.services.syncthing.url == null;
assert !(builtins.hasAttr "/syncthing/" vhost.locations);
assert !httpsSops.systemd.services.junix-portal-status.serviceConfig.PrivateUsers;
assert !studySvc.serviceConfig.PrivateUsers;
assert studySvc.serviceConfig.User == "portal-study-tracker";
assert studySvc.serviceConfig.StateDirectoryMode == "0700";
assert studySvc.environment.PORT == "18090";
assert studySvc.environment.HOST == "127.0.0.1";
assert studySvc.environment.APP_ENV == "production";
assert !(builtins.elem dummyCa httpOnly.security.pki.certificateFiles);
assert builtins.elem 80 httpOnly.networking.firewall.allowedTCPPorts;
assert !(builtins.elem 443 httpOnly.networking.firewall.allowedTCPPorts);
assert !httpVhost.forceSSL;
assert !(builtins.hasAttr "portal_tls_cert" httpOnly.sops.secrets);
assert httpVhost.locations."/raw-uri/".proxyPass == "http://127.0.0.1:18091";
assert httpOnly.systemd.services.junix-portal-status.serviceConfig.PrivateUsers;
assert !(builtins.hasAttr "portal_tls_cert" customTls.sops.secrets);
assert !(builtins.elem 443 customTls.networking.firewall.allowedTCPPorts);
assert customTls.services.nginx.virtualHosts.junixsrv.sslCertificate == "${dummyCert}";
assert customTls.services.nginx.virtualHosts.junixsrv.sslCertificateKey == "${dummyKey}";
assert builtins.hasContext customTls.services.nginx.virtualHosts.junixsrv.sslCertificate;
assert builtins.hasContext customTls.services.nginx.virtualHosts.junixsrv.sslCertificateKey;
assert hasFailedAssertion "custom.services.portal.tls:" halfTls;
assert hasFailedAssertion "custom.services.portal:" reservedCollision;
assert hasFailedAssertion "custom.services.portal.projects:" portCollision;
assert hasFailedAssertion "custom.services.portal.projects:" stripPrefixNoSlash;
assert hasFailedAssertion "custom.services.portal.projects:" unmanagedPortDup;
assert hasFailedAssertion "custom.services.portal.services:" multiTargetService;
assert hasFailedAssertion "custom.services.portal.services:" duplicateSubdomain;
assert hasFailedAssertion "custom.services.portal.services:" subdomainWithoutProxy;
assert serverHost.services.nginx.enable;
assert serverVhost.forceSSL;
assert builtins.elem 80 serverHost.networking.firewall.allowedTCPPorts;
assert builtins.elem 443 serverHost.networking.firewall.allowedTCPPorts;
assert serverHost.custom.services.portal.services.navidrome.subdomain == "music";
assert serverHost.custom.services.portal.services.navidrome.proxyPass == "http://127.0.0.1:4533";
assert serverHost.custom.services.portal.services.vikunja.subdomain == "tasks";
assert serverHost.custom.services.portal.services.radicale.subdomain == "cal";
assert serverHost.custom.services.portal.services.harmonia.port == 5000;
assert serverHost.custom.services.portal.services.syncthing.port == null;
assert serverHost.custom.services.portal.services.syncthing.location == null;
assert serverHost.services.litellm.enable;
assert serverHost.services.litellm.host == "127.0.0.1";
assert serverHost.services.litellm.port == 4000;
assert !serverHost.systemd.services.litellm.serviceConfig.DynamicUser;
assert !serverHost.systemd.services.litellm.serviceConfig.PrivateUsers;
assert !(builtins.elem pkgs.playwright-mcp serverHost.environment.systemPackages);
assert !(builtins.elem 4000 serverHost.networking.firewall.allowedTCPPorts);
assert serverHost.custom.services.portal.services.litellm.port == null;
assert serverHost.custom.services.portal.services.litellm.location == null;
pkgs.runCommand "portal-host-options" { } ''
  test -f ${serverVhost.root}/index.html
  test -f ${serverVhost.root}/style.css
  test -f ${serverVhost.root}/app.js
  test -f ${serverVhost.root}/portal-config.json
  test -f ${serverVhost.root}/favicon.svg
  test -f ${serverVhost.root}/icons/music.svg
  test -f ${serverVhost.root}/icons/tasks.svg
  test -f ${serverVhost.root}/icons/calendar.svg
  test -f ${serverVhost.root}/icons/sync.svg
  test -f ${serverVhost.root}/icons/package.svg
  test -f ${serverVhost.root}/icons/code.svg
  test -f ${serverVhost.root}/icons/globe.svg
  test -f ${serverVhost.root}/icons/chat.svg
  test -f ${serverVhost.root}/icons/bot.svg
  mkdir -p "$out"
''
