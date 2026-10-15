# Gruvbox Material: dark background, medium contrast, "mix" foreground.
# Values from sainnhe/gruvbox-material (autoload/gruvbox_material.vim).
# Plain data, not a module: read through the custom.theme.palette option.
rec {
  name = "Gruvbox Material Mix Dark Medium";

  # Backgrounds, darkest to lightest
  bg_dim = "#1b1b1b";
  bg0 = "#282828";
  bg1 = "#32302f";
  bg2 = "#32302f";
  bg3 = "#45403d";
  bg4 = "#45403d";
  bg5 = "#5a524c";
  bg_statusline1 = "#32302f";
  bg_statusline2 = "#3a3735";
  bg_statusline3 = "#504945";
  bg_current_word = "#3c3836";

  # Tinted backgrounds (selections, urgent and active states)
  bg_visual_red = "#4c3432";
  bg_visual_yellow = "#4f422e";
  bg_visual_green = "#3b4439";
  bg_visual_blue = "#374141";
  bg_visual_purple = "#443840";

  # Foregrounds and greys
  fg0 = "#e2cca9";
  fg1 = "#e2cca9";
  grey0 = "#7c6f64";
  grey1 = "#928374";
  grey2 = "#a89984";

  # Accents
  red = "#f2594b";
  orange = "#f28534";
  yellow = "#e9b143";
  green = "#b0b846";
  aqua = "#8bba7f";
  blue = "#80aa9e";
  purple = "#d3869b";

  # Focus, borders and highlights across the desktop
  accent = yellow;

  # Terminal colors, following the scheme's own terminal mapping (black is
  # bg5), with grey1 as a readable bright black. In mix, fg1 equals fg0, so
  # bright white matches white.
  ansi = [
    bg5 # 0 black
    red # 1 red
    green # 2 green
    yellow # 3 yellow
    blue # 4 blue
    purple # 5 magenta
    aqua # 6 cyan
    fg0 # 7 white
    grey1 # 8 bright black
    red # 9 bright red
    green # 10 bright green
    yellow # 11 bright yellow
    blue # 12 bright blue
    purple # 13 bright magenta
    aqua # 14 bright cyan
    fg1 # 15 bright white
  ];
}
