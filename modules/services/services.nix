{ ... }:
{
  imports = [
    ./syncthing.nix
    ./postgresql.nix
    ./i2pd.nix
    ./jellyfin.nix
    ./ArchiSteamFarm.nix
    ./wiki-js.nix
    ./openrgb.nix
  ];
}
