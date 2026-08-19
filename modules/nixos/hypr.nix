{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.hyprland;
in
{
  options.custom.desktop.hyprland = {
    enable = lib.mkEnableOption "Hyprland Wayland compositor";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      hypridle
      hyprpolkitagent
    ];

    programs = {
      hyprland.enable = true;
      hyprlock.enable = true;
    };
  };
}
