{
  services.syncthing = {
    enable = true;
    group = "users";
    user = "julian";
    configDir = "/home/julian/Documents/.config/syncthing";
    guiAddress = "0.0.0.0:8384";
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      devices = {
	"junixos" = {
	  id = "AGTVWZK-N2CFTWJ-GBQH4CJ-YU4BQBQ-LXCK7ZD-E7QP7K3-4PBNGEI-MJL4AAC";
	};
        "junixbook" = {
          id = "";
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
