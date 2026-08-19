{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.gaming;
in
{
  options.custom.desktop.gaming = {
    enable = lib.mkEnableOption "gaming configuration (Steam, Lutris, Heroic, Prism Launcher, Gamemode)";
    user = lib.mkOption {
      type = lib.types.str;
      default = config.custom.user;
      description = "Primary user for gaming group assignment";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      itch
      lutris
      heroic
      r2modman

      protonup-ng
      protontricks
      mangohud

      # Updated Prism Launcher configuration
      (prismlauncher.override {
        jdks = [
          jdk25 # The version you confirmed works
          jdk21 # Standard for modern Minecraft (1.20.5+)
          jdk17 # Standard for 1.18 - 1.20.4
          jdk8 # For very old legacy versions
        ];
      })

      ddnet
      osu-lazer-bin # "-bin" is needed to submit scores and play online multiplayer
    ];

    programs = {
      steam = {
        enable = true;
        remotePlay.openFirewall = true;
        localNetworkGameTransfers.openFirewall = true;
      };
      gamemode.enable = true;
      gamescope = {
        enable = true;
        capSysNice = true;
      };
    };

    users.users.${cfg.user}.extraGroups = [ "gamemode" ];
  };
}
