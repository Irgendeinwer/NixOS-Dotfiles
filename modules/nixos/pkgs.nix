{ pkgs, ... }:
{

  environment.systemPackages = with pkgs; [
    antigravity-ide-fhs
    antigravity-cli

    appimage-run

    unar
    yazi

    keepassxc

    qbittorrent-nox
  ];
}
