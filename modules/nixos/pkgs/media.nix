{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    mediainfo
    pear-desktop
    celluloid
    vlc
    feishin
    rush-lyrics
    imv
  ];
}
