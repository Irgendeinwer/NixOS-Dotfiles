{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    pear-desktop
    celluloid
    vlc
    feishin
    rush-lyrics
  ];
}
