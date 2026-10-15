{ pkgs, ... }:
let
  # Drawn as SVG in assets/ and rasterized at build time, so the PNG can never
  # drift from its source.
  logo = pkgs.runCommand "fastfetch-logo.png" { nativeBuildInputs = [ pkgs.resvg ]; } ''
    resvg --width 1024 ${../../assets/icon.svg} $out
  '';
in
{
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        source = "${logo}";
        # Columns wide; height auto-scales to preserve the square aspect.
        # (With neither set, fastfetch renders the 1024px original.)
        width = 40;
        padding = {
          right = 2;
        };
      };
      display = {
        separator = "  ";
        color = "yellow";
      };
      modules = [
        "title"
        "separator"
        "os"
        "host"
        "kernel"
        "uptime"
        "packages"
        "shell"
        "display"
        "wm"
        "terminal"
        "cpu"
        "gpu"
        "memory"
        "disk"
        "break"
        "colors"
      ];
    };
  };
}
