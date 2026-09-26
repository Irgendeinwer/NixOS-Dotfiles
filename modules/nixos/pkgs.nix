{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.tools;
in
{
  options.custom.desktop.tools = {
    enable = lib.mkEnableOption "desktop productivity and development utilities (KeePassXC, Yazi, Antigravity, qBittorrent, etc.)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      antigravity-ide-fhs
      antigravity-cli
      appimage-run
      unar
      yazi
      keepassxc
      qbittorrent-nox
    ];
  };
}
