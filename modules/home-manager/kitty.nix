{
  programs.kitty = {
    enable = true;

    font = {
      # Generic family until the nerd-font verdict lands; do not pin a
      # fragile family name here.
      name = "monospace";
      size = 11;
    };

    settings = {
      # Gruvbox dark
      foreground = "#ebdbb2";
      background = "#282828";
      selection_foreground = "#282828";
      selection_background = "#d79921";
      cursor = "#fabd2f";
      cursor_text_color = "#282828";
      url_color = "#83a598";

      # black
      color0 = "#282828";
      color8 = "#928374";
      # red
      color1 = "#cc241d";
      color9 = "#fb4934";
      # green
      color2 = "#98971a";
      color10 = "#b8bb26";
      # yellow
      color3 = "#d79921";
      color11 = "#fabd2f";
      # blue
      color4 = "#458588";
      color12 = "#83a598";
      # magenta
      color5 = "#b16286";
      color13 = "#d3869b";
      # cyan
      color6 = "#689d6a";
      color14 = "#8ec07c";
      # white
      color7 = "#a89984";
      color15 = "#ebdbb2";

      # Borders and tabs
      active_border_color = "#d79921";
      inactive_border_color = "#3c3836";
      bell_border_color = "#fb4934";
      active_tab_foreground = "#282828";
      active_tab_background = "#d79921";
      inactive_tab_foreground = "#a89984";
      inactive_tab_background = "#3c3836";
      tab_bar_background = "#282828";

      # Behavior
      window_padding_width = 8;
      copy_on_select = "yes";
      confirm_os_window_close = 0;
      enable_audio_bell = "no";
    };
  };
}
