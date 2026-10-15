{
  config,
  lib,
  pkgs,
  ...
}:
let
  p = config.custom.theme.palette;

  # Color variables for layout.rasi, generated from the palette.
  colors = ''
    * {
      bg0: ${p.bg0};
      fg1: ${p.fg1};
      grey2: ${p.grey2};
      red: ${p.red};
      yellow: ${p.yellow};
      bg-visual-red: ${p.bg_visual_red};
      bg-visual-yellow: ${p.bg_visual_yellow};
      surface: ${p.bg_dim}e6;

      foreground: ${p.grey0};
      background-color: transparent;
      highlight: underline bold ${p.accent};
    }

  '';
in
{
  programs.rofi = {
    enable = true;
    # A string path, so Home Manager emits @theme "<file>" for it.
    theme = "${pkgs.writeText "gruvbox-material.rasi" (colors + builtins.readFile ./layout.rasi)}";
    # App icons in the launcher and window list from the desktop icon theme
    settings = lib.mkIf (config.gtk.iconTheme != null) {
      icon-theme = config.gtk.iconTheme.name;
    };
  };
}
