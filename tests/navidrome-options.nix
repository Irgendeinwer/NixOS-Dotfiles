{
  nixpkgs,
  pkgs,
  self,
}:
let
  inherit (nixpkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;

  evalNavidrome =
    extraConfig:
    (lib.nixosSystem {
      inherit system;
      modules = [
        {
          options.custom.user = lib.mkOption {
            type = lib.types.str;
            default = "julian";
          };
        }
        ../modules/services/syncthing.nix
        ../modules/services/navidrome.nix
        {
          networking.hostName = "navidrome-test";
          system.stateVersion = "26.11";
        }
        extraConfig
      ];
    }).config;

  disabled = evalNavidrome { };

  bareMetal = evalNavidrome {
    custom.services.navidrome.enable = true;
  };

  containerSync = evalNavidrome {
    boot.isContainer = true;
    custom.services = {
      syncthing.enable = true;
      navidrome.enable = true;
    };
  };

  externalLibrary = evalNavidrome {
    custom.services.navidrome = {
      enable = true;
      openFirewall = false;
      host = "::";
      port = 4534;
      musicFolder = "/srv/music";
    };
  };

  relativeFolder = evalNavidrome {
    custom.services.navidrome = {
      enable = true;
      musicFolder = "music";
    };
  };

  reverseProxied = evalNavidrome {
    custom.services.navidrome = {
      enable = true;
      reverseProxy.enable = true;
    };
  };

  hasFailedAssertion =
    prefix: cfg: lib.any (a: !a.assertion && lib.hasPrefix prefix a.message) cfg.assertions;

  musicDirRule = bareMetal.systemd.tmpfiles.settings.navidromeDirs."/home/julian/music".d;
  desktopHost = self.nixosConfigurations.junixos.config;
  laptopHost = self.nixosConfigurations.junixbook.config;
  serverHost = self.nixosConfigurations.junixsrv.config;
in
assert !disabled.services.navidrome.enable;
assert bareMetal.services.navidrome.enable;
assert bareMetal.services.navidrome.openFirewall;
assert builtins.elem 4533 bareMetal.networking.firewall.allowedTCPPorts;
assert bareMetal.services.navidrome.settings.Address == "0.0.0.0";
assert bareMetal.services.navidrome.settings.Port == 4533;
assert bareMetal.services.navidrome.settings.MusicFolder == "/home/julian/music";
assert bareMetal.services.navidrome.settings.Scanner.PurgeMissing == "always";
assert builtins.elem "users" bareMetal.users.users.navidrome.extraGroups;
assert musicDirRule.mode == ":0750";
assert musicDirRule.user == ":julian";
assert musicDirRule.group == ":users";
assert bareMetal.systemd.services.navidrome.serviceConfig.PrivateUsers;
assert bareMetal.systemd.services.navidrome.serviceConfig.ProtectHome == "tmpfs";
assert !containerSync.systemd.services.navidrome.serviceConfig.PrivateUsers;
assert containerSync.systemd.services.navidrome.serviceConfig.ProtectHome == "tmpfs";
assert builtins.elem "syncthing.service" containerSync.systemd.services.navidrome.after;
assert !externalLibrary.services.navidrome.openFirewall;
assert !(builtins.elem 4534 externalLibrary.networking.firewall.allowedTCPPorts);
assert externalLibrary.services.navidrome.settings.Address == "[::]";
assert externalLibrary.services.navidrome.settings.Port == 4534;
assert externalLibrary.systemd.services.navidrome.serviceConfig.ProtectHome == true;
assert hasFailedAssertion "custom.services.navidrome.musicFolder:" relativeFolder;
assert !reverseProxied.services.navidrome.openFirewall;
assert reverseProxied.services.navidrome.settings.Address == "127.0.0.1";
assert !(builtins.elem 4533 reverseProxied.networking.firewall.allowedTCPPorts);
assert desktopHost.services.jellyfin.enable;
assert !desktopHost.services.navidrome.enable;
assert !laptopHost.services.jellyfin.enable;
assert !laptopHost.services.navidrome.enable;
assert !serverHost.services.jellyfin.enable;
assert serverHost.services.navidrome.enable;
assert serverHost.custom.services.navidrome.reverseProxy.enable;
assert serverHost.services.navidrome.settings.Address == "127.0.0.1";
assert serverHost.services.navidrome.settings.MusicFolder == "/home/julian/music";
assert !(builtins.elem 4533 serverHost.networking.firewall.allowedTCPPorts);
assert !serverHost.systemd.services.navidrome.serviceConfig.PrivateUsers;
assert serverHost.systemd.services.navidrome.serviceConfig.ProtectHome == "tmpfs";
pkgs.runCommand "navidrome-host-options" { } ''
  mkdir -p "$out"
''
