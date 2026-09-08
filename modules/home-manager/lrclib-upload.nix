{ pkgs, ... }:

let
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
{
  home.packages = [ lrclib-upload ];
}
