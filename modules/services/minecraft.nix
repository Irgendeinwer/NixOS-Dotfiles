{ pkgs, lib, ... }:
let
  modpack = pkgs.fetchPackwizModpack {
    url = "https://codeberg.org/Irgendeinwer/fabric-packwiz/raw/tag/v1.3/pack.toml";
    packHash = "sha256-Hv1CsvokqrzrlHEJTNXyZj1o1dFGl0y0+NTUgqTh/ks=";
    manifestHash = "0bypfaf34bd95x4rh8hlb5ybps5m1g999kqw3bvwgfsvpxplrqs3"; 
  };
  mcVersion = modpack.manifest.versions.minecraft;
  fabricVersion = modpack.manifest.versions.fabric;
  serverVersion = lib.replaceStrings [ "." ] [ "_" ] "fabric-${mcVersion}";
in
{
  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;
    dataDir = "/var/minecraft";
    
    servers.cool-modpack = {
	enable = true;
	whitelist = { # You can use mcuuid.net
	   SI9M4 = "8c3c5600-2f7e-49f9-9590-c2d43abfe467";
	   Vartroc = "ce3a67ad-3a84-4bcb-a809-ad9d7330de01";
	   S9ma = "b6416a11-4e94-4664-a4f8-233c2589efe0";
	};
	serverProperties = {
	   white-list = true;
	   motd = "Fabric on NixOS, btw";
	   max-players = 10;
	   spawn-protection = 0;
	   difficulty = 3;
	};
	jvmOpts = "-Xms6G -Xmx3G";
	package = pkgs.fabricServers.${serverVersion}.override { loaderVersion = fabricVersion; };
	symlinks = {
	   "mods" = "${modpack}/mods";
	};
    };
  };
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "minecraft-server"
  ];
}
