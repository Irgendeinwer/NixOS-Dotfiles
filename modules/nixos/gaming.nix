{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # itch WAS DOWN SO XD
    lutris
    heroic
    r2modman

    protonup
    protontricks
    mangohud

    ddnet
    osu-lazer-bin # "-bin" is needed to submit scores and play online multiplayer
  ];
  programs = {
    steam.enable = true;
    gamemode.enable = true;
  };
}
