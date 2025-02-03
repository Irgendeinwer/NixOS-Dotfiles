{ ... }:
{
  imports = [
    ./postgresql.nix
    ./jellyfin.nix
    ./ArchiSteamFarm.nix
    ./wiki-js.nix
  ];
}
