{
  inputs,
  nixpkgs,
  pkgs,
  self,
}:
let
  inherit (nixpkgs) lib;

  desktopHost = self.nixosConfigurations.junixos.config;
  laptopHost = self.nixosConfigurations.junixbook.config;
  serverHost = self.nixosConfigurations.junixsrv.config;

  desktopHome = desktopHost.home-manager.users.${desktopHost.custom.user};
  laptopHome = laptopHost.home-manager.users.${laptopHost.custom.user};
  serverHome = serverHost.home-manager.users.${serverHost.custom.user};

  noTimerHost =
    (self.nixosConfigurations.junixos.extendModules {
      modules = [
        {
          custom.desktop.missnix.timer.enable = false;
        }
      ];
    }).config;
  noTimerHome = noTimerHost.home-manager.users.${noTimerHost.custom.user};

  standalonePkgs = import inputs.nixpkgs {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  standaloneEnabled = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = standalonePkgs;
    extraSpecialArgs = { inherit inputs; };
    modules = [
      ../modules/home-manager
      {
        home.username = "test";
        home.homeDirectory = "/home/test";
        home.stateVersion = "24.05";
        custom.desktop.missnix = {
          enable = true;
          timer.onCalendar = "*-*-* 18:00:00";
        };
      }
    ];
  };
  standaloneCfg = standaloneEnabled.config;
in
assert desktopHost.custom.desktop.missnix.enable;
assert desktopHost.custom.desktop.missnix.musicDirs == [ "/home/irgendeinwer/music" ];
assert desktopHome.programs.missnix.enable;
assert desktopHome.home.sessionVariables.MISSNIX_DEFAULT_DARK_MODE == "true";
assert desktopHome.home.sessionVariables.MISSNIX_DEFAULT_ACCENT_HEX == "#E9B143";
assert !laptopHost.custom.desktop.missnix.enable;
assert !laptopHome.programs.missnix.enable;
assert !serverHost.custom.desktop.missnix.enable;
assert lib.any (p: (p.pname or "") == "missnix") desktopHome.home.packages;
assert !(lib.any (p: (p.pname or "") == "missnix") laptopHome.home.packages);
assert !(lib.any (p: (p.pname or "") == "missnix") serverHome.home.packages);
assert desktopHome.systemd.user.services ? missnix-check;
assert lib.hasInfix "--notify" desktopHome.systemd.user.services.missnix-check.Service.ExecStart;
assert desktopHome.systemd.user.timers ? missnix-check;
assert desktopHome.systemd.user.timers.missnix-check.Timer.Persistent;
assert desktopHome.systemd.user.timers.missnix-check.Timer.OnCalendar == "daily";
assert !(laptopHome.systemd.user.timers ? missnix-check);
assert !(noTimerHome.systemd.user.services ? missnix-check);
assert !(noTimerHome.systemd.user.timers ? missnix-check);
assert lib.any (p: (p.pname or "") == "missnix") noTimerHome.home.packages;
assert standaloneCfg.systemd.user.timers.missnix-check.Timer.OnCalendar == "*-*-* 18:00:00";
assert lib.hasSuffix ".drv" self.packages.${pkgs.stdenv.hostPlatform.system}.missnix.drvPath;
assert lib.hasSuffix ".drv" standaloneCfg.home.activationPackage.drvPath;
pkgs.runCommand "missnix-options" { } ''
  mkdir -p "$out"
''
