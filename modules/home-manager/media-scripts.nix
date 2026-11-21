{
  lib,
  osConfig ? null,
  pkgs,
  ...
}:

let
  mediaEnabled = if osConfig != null then (osConfig.custom.desktop.media.enable or false) else true;
  # Fall back to direct import so standalone Home Manager evaluations without
  # repository overlays still resolve the shared script packages.
  scripts = pkgs.custom or (import ../../pkgs/scripts { inherit lib pkgs; });
in
lib.mkIf mediaEnabled {
  home.packages = [
    scripts.listen
    scripts.lrclib-upload
    scripts.zip2opus
  ];
}
