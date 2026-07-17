{ pkgs, ... }:
{
  imports = [
    ./pkgs/browsers.nix
    ./pkgs/flexing.nix
    ./pkgs/messaging.nix
    ./pkgs/media.nix
  ];

  environment.systemPackages = with pkgs; [
    antigravity-fhs
    antigravity-cli

    appimage-run

    unar
    yazi

    keepassxc

    qbittorrent-nox
  ];
}
