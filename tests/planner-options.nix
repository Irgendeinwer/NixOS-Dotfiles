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
  dummyEnv = pkgs.writeText "dummy-vikunja.env" "VIKUNJA_SERVICE_SECRET=test\n";
  dummyHtpasswd = pkgs.writeText "dummy-radicale.htpasswd" "julian:$2y$05$test\n";

  evalPlanner =
    extraConfig:
    (lib.nixosSystem {
      inherit system;
      modules = [
        sopsModule
        {
          options.custom.user = lib.mkOption {
            type = lib.types.str;
            default = "julian";
          };
        }
        ../modules/nixos/pki.nix
        ../modules/services/portal.nix
        ../modules/services/planner.nix
        {
          networking.hostName = "junixsrv";
          time.timeZone = "Europe/Berlin";
          system.stateVersion = "26.11";
        }
        extraConfig
      ];
    }).config;

  disabled = evalPlanner { };

  enabledSops = evalPlanner {
    boot.isContainer = true;
    custom.system.security.localCa.certificateFile = dummyCa;
    custom.services = {
      portal.enable = true;
      planner.enable = true;
    };
  };

  customFiles = evalPlanner {
    custom.system.security.localCa = {
      enable = false;
      certificateFile = dummyCa;
    };
    custom.services = {
      portal = {
        enable = true;
        tls.enable = false;
      };
      planner = {
        enable = true;
        vikunja.environmentFile = dummyEnv;
        radicale = {
          htpasswdFile = dummyHtpasswd;
          mobileCaldavPath = false;
        };
      };
    };
  };

  portCollision = evalPlanner {
    custom.services.planner = {
      enable = true;
      vikunja.port = 4400;
      radicale.port = 4400;
    };
  };

  hasFailedAssertion =
    prefix: cfg: lib.any (a: !a.assertion && lib.hasPrefix prefix a.message) cfg.assertions;

  tasksVhost = enabledSops.services.nginx.virtualHosts."tasks.junixsrv.internal";
  calVhost = enabledSops.services.nginx.virtualHosts."cal.junixsrv.internal";
  defaultVhost = enabledSops.services.nginx.virtualHosts.junixsrv;

  desktopHost = self.nixosConfigurations.junixos.config;
  laptopHost = self.nixosConfigurations.junixbook.config;
  serverHost = self.nixosConfigurations.junixsrv.config;
  desktopAliases = desktopHost.custom.system.remoteBuilder.extraHostAliases;

  desktopHome = desktopHost.home-manager.users.${desktopHost.custom.user};
  laptopHome = laptopHost.home-manager.users.${laptopHost.custom.user};
  desktopDaemonUnit = desktopHome.systemd.user.services.junix-plan-daemon.Unit;
  desktopPlanSource = "${desktopHome.xdg.configFile."junix-plan/config.json".source}";
  desktopPlanJson = builtins.fromJSON desktopHome.xdg.configFile."junix-plan/config.json".text;
  laptopPlanJson = builtins.fromJSON laptopHome.xdg.configFile."junix-plan/config.json".text;
in
assert !disabled.services.vikunja.enable;
assert !disabled.services.radicale.enable;
assert !(builtins.hasAttr "vikunja_env" disabled.sops.secrets);
assert !(builtins.hasAttr "radicale_htpasswd" disabled.sops.secrets);
assert enabledSops.services.vikunja.enable;
assert enabledSops.services.vikunja.address == "127.0.0.1";
assert enabledSops.services.vikunja.port == 3456;
assert enabledSops.services.vikunja.frontendScheme == "https";
assert enabledSops.services.vikunja.frontendHostname == "tasks.junixsrv.internal";
assert !enabledSops.services.vikunja.settings.service.enableregistration;
assert !enabledSops.services.vikunja.settings.service.enablelinksharing;
assert enabledSops.services.vikunja.settings.service.maxitemsperpage == 200;
assert !enabledSops.systemd.services.vikunja.serviceConfig.DynamicUser;
assert enabledSops.systemd.services.vikunja.serviceConfig.User == "vikunja";
assert !enabledSops.systemd.services.vikunja.serviceConfig.PrivateUsers;
assert enabledSops.services.radicale.enable;
assert enabledSops.services.radicale.settings.server.hosts == [ "127.0.0.1:5232" ];
assert enabledSops.services.radicale.settings.auth.type == "htpasswd";
assert enabledSops.services.radicale.settings.auth.htpasswd_encryption == "bcrypt";
assert !enabledSops.systemd.services.radicale.serviceConfig.PrivateUsers;
assert builtins.hasAttr "vikunja_env" enabledSops.sops.secrets;
assert builtins.hasAttr "radicale_htpasswd" enabledSops.sops.secrets;
assert builtins.elem "vikunja.service" enabledSops.sops.secrets.vikunja_env.restartUnits;
assert builtins.elem "radicale.service" enabledSops.sops.secrets.radicale_htpasswd.restartUnits;
assert tasksVhost.forceSSL;
assert tasksVhost.locations."/".proxyPass == "http://127.0.0.1:3456";
assert lib.hasInfix "client_max_body_size 64M;" tasksVhost.locations."/".extraConfig;
assert calVhost.forceSSL;
assert calVhost.locations."/".proxyPass == "http://127.0.0.1:5232";
assert defaultVhost.locations."= /cal".return == "308 /cal/";
assert defaultVhost.locations."/cal/".proxyPass == "http://127.0.0.1:5232/";
assert lib.hasInfix "X-Script-Name /cal" defaultVhost.locations."/cal/".extraConfig;
assert !(builtins.hasAttr "vikunja_env" customFiles.sops.secrets);
assert !(builtins.hasAttr "radicale_htpasswd" customFiles.sops.secrets);
assert customFiles.services.vikunja.frontendScheme == "http";
assert !(builtins.hasAttr "/cal/" customFiles.services.nginx.virtualHosts.junixsrv.locations);
assert hasFailedAssertion "custom.services.planner:" portCollision;
assert serverHost.services.vikunja.enable && serverHost.services.radicale.enable;
assert !(builtins.elem 3456 serverHost.networking.firewall.allowedTCPPorts);
assert !(builtins.elem 5232 serverHost.networking.firewall.allowedTCPPorts);
assert desktopHost.custom.desktop.planner.enable && laptopHost.custom.desktop.planner.enable;
assert builtins.elem "tasks.junixsrv.internal" desktopAliases;
assert builtins.elem "cal.junixsrv.internal" desktopAliases;
assert builtins.elem "music.junixsrv.internal" desktopAliases;
assert desktopHome.systemd.user.services ? junix-plan-daemon;
assert laptopHome.systemd.user.services ? junix-plan-daemon;
assert desktopDaemonUnit.X-Restart-Triggers == [ desktopPlanSource ];
assert desktopPlanJson.vikunja_url == "https://tasks.junixsrv.internal";
assert desktopPlanJson.radicale_url == "https://cal.junixsrv.internal";
assert desktopPlanJson.calendar_path == "/julian/personal/";
assert desktopPlanJson.default_project == "Inbox";
assert laptopPlanJson.vikunja_url == "https://tasks.junixsrv.internal";
assert laptopPlanJson.radicale_url == "https://cal.junixsrv.internal";
assert laptopPlanJson.default_project == "Inbox";
pkgs.runCommand "planner-host-options" { } ''
  mkdir -p "$out"
''
