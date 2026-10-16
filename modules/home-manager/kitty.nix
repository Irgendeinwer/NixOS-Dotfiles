{ config, lib, ... }:
let
  p = config.custom.theme.palette;
  # color0 .. color15 from the palette's terminal colors
  ansi = lib.listToAttrs (
    lib.imap0 (i: color: {
      name = "color${toString i}";
      value = color;
    }) p.ansi
  );
in
{
  programs.kitty = {
    enable = true;

    font = {
      # Generic on purpose: fontconfig's monospace alias resolves to
      # Fira Code Nerd Font Mono (modules/nixos/fonts.nix).
      name = "monospace";
      size = 11;
    };

    settings = ansi // {
      # Gruvbox Material (custom.theme.palette)
      foreground = p.fg0;
      background = p.bg0;
      selection_foreground = p.bg0;
      selection_background = p.fg0;
      cursor = p.grey2;
      cursor_text_color = "background";
      url_color = p.blue;

      # Borders and tabs
      active_border_color = p.accent;
      inactive_border_color = p.bg3;
      bell_border_color = p.red;
      active_tab_foreground = p.bg0;
      active_tab_background = p.accent;
      inactive_tab_foreground = p.grey2;
      inactive_tab_background = p.bg1;
      tab_bar_background = p.bg0;

      # Behavior
      window_padding_width = 8;
      copy_on_select = "yes";
      confirm_os_window_close = 0;
      enable_audio_bell = "no";
    };

    # Word-wise deletion: ^W backward-kill-word, ESC d kill-word (zsh emacs mode).
    keybindings = {
      "ctrl+backspace" = "send_text all \\x17";
      "ctrl+delete" = "send_text all \\ed";
    };
  };
}
