{ ... }:
{
  imports = [
    ./postgresql.nix
    ./i2pd.nix
    ./jellyfin.nix
    ./ArchiSteamFarm.nix
    ./wiki-js.nix
  ];
}
