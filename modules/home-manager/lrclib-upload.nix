{
  lib,
  osConfig ? null,
  pkgs,
  ...
}:

let
  mediaEnabled = if osConfig != null then (osConfig.custom.desktop.media.enable or false) else true;

  lrclib-upload = pkgs.writeShellApplication {
    name = "lrclib-upload";

    runtimeInputs = with pkgs; [
      python3
      ffmpeg
    ];

    text = ''
      exec python3 "${./scripts/lrclib-upload.py}" "$@"
    '';
  };
in
lib.mkIf mediaEnabled {
  home.packages = [ lrclib-upload ];
}
