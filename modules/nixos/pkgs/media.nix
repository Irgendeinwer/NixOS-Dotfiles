{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.media;
in
{
  options.custom.desktop.media = {
    enable = lib.mkEnableOption "desktop media players and media tools";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      mediainfo
      pear-desktop
      celluloid
      vlc
      feishin
      rush-lyrics
      imv
      projectm-sdl-cpp
    ];
  };
}
