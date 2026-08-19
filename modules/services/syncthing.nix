{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.syncthing;
in
{
  options.custom.services.syncthing = {
    enable = lib.mkEnableOption "Syncthing file synchronization";
    user = lib.mkOption {
      type = lib.types.str;
      default = "julian";
      description = "User to run Syncthing under";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open Syncthing sync (TCP/UDP 22000) and discovery (UDP 21027) ports in firewall";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 22000 ];
      allowedUDPPorts = [
        22000
        21027
      ];
    };

    services.syncthing = {
      enable = true;
      group = "users";
      user = cfg.user;
      configDir = "/home/${cfg.user}/.config/syncthing";
      guiAddress = "0.0.0.0:8384";
      overrideDevices = true;
      overrideFolders = true;
      settings = {
        devices = {
          "junixos" = {
            id = "4MAINN2-ZRIWH6F-GU47MQP-4RZEUZX-E7OJJMU-H3HVRUF-2JLGKMI-AUP5CQQ";
          };
          "junixbook" = {
            id = "XVJL4SC-76BTLAU-7KBGIFQ-GLOYBAR-OGFVIBM-R7H3DZW-MT7YYMP-D4VUVAS";
          };
          "MobileF6" = {
            id = "3TDB3IH-BQSLKAR-CTF76VY-IWSYB3S-X2WMD4U-P5QFA23-RBKPITT-U7M3FA6";
          };
        };
        folders = {
          "Documents" = {
            path = "/home/${cfg.user}/Documents";
            devices = [
              "junixos"
              "junixbook"
              "MobileF6"
            ];
            versioning = {
              type = "staggered";
              params = {
                cleanInterval = "3600"; # 1 hour
                maxAge = "7776000"; # 90 days
              };
            };
          };
          "Schule-25-26" = {
            path = "/home/${cfg.user}/Schule-25-26";
            devices = [
              "junixos"
              "junixbook"
              "MobileF6"
            ];
          };
          "Music" = {
            path = "/home/${cfg.user}/music";
            devices = [
              "junixos"
              "junixbook"
              "MobileF6"
            ];
          };
          "E-Books" = {
            path = "/home/${cfg.user}/E-Books";
            devices = [
              "junixos"
              "junixbook"
              "MobileF6"
            ];
          };
          "#Noice" = {
            path = "/home/${cfg.user}/stuff/#Noice";
            devices = [
              "junixos"
              "MobileF6"
            ];
          };
        };
      };
    };
  };
}
