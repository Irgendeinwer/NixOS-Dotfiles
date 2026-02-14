{ pkgs, ... }:
{
  imports = [
    ./pkgs/browsers.nix
    ./pkgs/flexing.nix
    ./pkgs/messaging.nix
    ./pkgs/streaming.nix
  ];

  environment.systemPackages = with pkgs; [
    antigravity-fhs

    appimage-run

    unar
    yazi

    keepassxc

    qbittorrent-nox
  ];
}
