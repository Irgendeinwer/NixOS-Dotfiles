{
  config,
  lib,
  osConfig ? null,
  ...
}:
let
  # Same gate as hyprland.nix: skip when another compositor is in use
  hyprlandEnabled =
    if osConfig != null then (osConfig.custom.desktop.hyprland.enable or false) else true;
in
lib.mkIf hyprlandEnabled {
  programs.hyprshot = {
    enable = true;
    saveLocation = "${config.home.homeDirectory}/Screenshots";
  };
}
