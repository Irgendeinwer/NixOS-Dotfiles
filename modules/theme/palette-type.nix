{ lib }:
let
  # Consumers append alpha channels, strip '#', and convert RGB components;
  # accepting arbitrary strings here would produce invalid configuration later.
  color = lib.types.strMatching "#[0-9a-fA-F]{6}";
  colorOption = lib.mkOption {
    type = color;
    description = "An RGB color in #RRGGBB form.";
  };
  optionalColorOption = lib.mkOption {
    type = lib.types.nullOr color;
    default = null;
    description = "Optional RGB color in #RRGGBB form; consumers choose a fallback when null.";
  };

  # These roles were already consumed by the desktop or terminal modules.
  colors = [
    "bg_dim"
    "bg0"
    "bg1"
    "bg3"
    "bg5"
    "bg_statusline2"
    "bg_visual_red"
    "bg_visual_yellow"
    "fg0"
    "fg1"
    "grey0"
    "grey1"
    "grey2"
    "red"
    "orange"
    "yellow"
    "green"
    "aqua"
    "blue"
    "purple"
    "accent"
  ];
  # Extra roles used by the Neovim theme. Alternative palettes that predate
  # these fields can omit them and use the related shared colors instead.
  optionalColors = [
    "bg2"
    "bg4"
    "bg_statusline1"
    "bg_statusline3"
    "bg_current_word"
    "bg_visual_green"
    "bg_visual_blue"
    "bg_visual_purple"
    "bg_diff_red"
    "bg_diff_green"
    "bg_diff_blue"
    "bg_red"
    "bg_green"
    "bg_yellow"
  ];
in
lib.types.submodule {
  # Keep room for consumers to add their own keys without modifying this type.
  freeformType = lib.types.attrsOf lib.types.anything;
  options =
    lib.genAttrs colors (_: colorOption)
    // lib.genAttrs optionalColors (_: optionalColorOption)
    // {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Custom";
        description = "Human-readable palette name.";
      };
      ansi = lib.mkOption {
        type = lib.types.listOf color;
        description = "The 16 terminal colors, in ANSI order.";
      };
    };
}
