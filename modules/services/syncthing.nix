{
  services.syncthing = {
    enable = true;
    group = "users";
    user = "julian";
    configDir = "/home/julian/.config/syncthing";
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
          path = "/home/julian/Documents";
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
          path = "/home/julian/Schule-25-26";
          devices = [
            "junixos"
            "junixbook"
            "MobileF6"
          ];
        };
        "Music" = {
          path = "/home/julian/music";
          devices = [
            "junixos"
            "junixbook"
            "MobileF6"
          ];
        };
        "#Noice" = {
          path = "/home/julian/stuff/#Noice";
          devices = [
            "junixos"
            "MobileF6"
          ];
        };
      };
    };
  };
}
