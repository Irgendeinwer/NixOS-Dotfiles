{
  config,
  lib,
  ...
}:
let
  p = config.custom.theme.palette;
  inherit (import ../theme/lib.nix { inherit lib; }) cterm;
  withCterm = color: [
    color
    (cterm color)
  ];
  fallback = value: alternative: if value == null then alternative else value;

  # The plugin has a few more roles than the shared desktop palette. Optional
  # roles fall back to related shared colors so existing alternative palettes
  # do not need to grow Neovim-specific entries just to remain usable.
  colors = {
    inherit (p)
      bg_dim
      bg0
      bg1
      bg3
      bg5
      bg_statusline2
      bg_visual_red
      bg_visual_yellow
      fg0
      fg1
      grey0
      grey1
      grey2
      red
      orange
      yellow
      green
      aqua
      blue
      purple
      ;
    bg2 = fallback p.bg2 p.bg1;
    bg4 = fallback p.bg4 p.bg3;
    bg_statusline1 = fallback p.bg_statusline1 p.bg1;
    bg_statusline3 = fallback p.bg_statusline3 p.bg3;
    bg_current_word = fallback p.bg_current_word p.bg3;
    bg_visual_green = fallback p.bg_visual_green p.bg3;
    bg_visual_blue = fallback p.bg_visual_blue p.bg3;
    bg_visual_purple = fallback p.bg_visual_purple p.bg3;
    bg_diff_red = fallback p.bg_diff_red p.bg_visual_red;
    bg_diff_green = fallback p.bg_diff_green (fallback p.bg_visual_green p.bg3);
    bg_diff_blue = fallback p.bg_diff_blue (fallback p.bg_visual_blue p.bg3);
    bg_red = fallback p.bg_red p.red;
    bg_green = fallback p.bg_green p.green;
    bg_yellow = fallback p.bg_yellow p.yellow;
  };

  strongSection = bg: {
    fg = p.bg0;
    inherit bg;
    gui = "bold";
  };
in
{
  programs.nixvim = {
    colorschemes.gruvbox-material = {
      enable = true;
      settings = {
        background = "medium";
        foreground = "mix";
        enable_bold = 1;
        colors_override = lib.mapAttrs (_: withCterm) colors;
        # The plugin otherwise duplicates colors 0-7 into the bright slots.
        disable_terminal_colors = 1;
      };
    };

    # Neovim's embedded terminal and Kitty use the same complete ANSI palette.
    globals = lib.listToAttrs (
      lib.imap0 (i: color: lib.nameValuePair "terminal_color_${toString i}" color) p.ansi
    );

    # Lualine's built-in gruvbox-material theme has a separate hardcoded
    # palette. Give it matching colors instead of relying on theme = "auto".
    plugins.lualine.settings.options.theme = {
      normal = {
        a = strongSection p.grey2;
        b = {
          fg = p.fg0;
          bg = fallback p.bg_statusline3 p.bg3;
        };
        c = {
          fg = p.fg0;
          bg = fallback p.bg_statusline1 p.bg1;
        };
      };
      command.a = strongSection p.blue;
      insert.a = strongSection p.green;
      replace.a = strongSection p.yellow;
      terminal.a = strongSection p.purple;
      visual.a = strongSection p.red;
      inactive.a = {
        fg = p.fg0;
        bg = fallback p.bg_statusline3 p.bg3;
      };
    };
  };
}
