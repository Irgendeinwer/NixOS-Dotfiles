{ config, lib, ... }:
let
  p = config.custom.theme.palette;

  # Same roles as btop's bundled gruvbox_material_dark theme, filled in from
  # custom.theme.palette. Graphs blank out their _mid and _end colors to stay
  # single-colored: a missing key would fall back to btop's default theme.
  theme = {
    main_bg = p.bg0;
    main_fg = p.fg0;
    title = p.fg0;
    hi_fg = p.red;
    selected_bg = p.accent;
    selected_fg = p.bg0;
    inactive_fg = p.bg0;
    graph_text = p.bg5;
    proc_misc = p.green;
    cpu_box = p.grey0;
    mem_box = p.grey0;
    net_box = p.grey0;
    proc_box = p.grey0;
    div_line = p.grey0;
    temp_start = p.blue;
    temp_mid = p.orange;
    temp_end = p.red;
    cpu_start = p.green;
    cpu_mid = p.yellow;
    cpu_end = p.red;
    free_start = p.aqua;
    free_mid = "";
    free_end = "";
    cached_start = p.blue;
    cached_mid = "";
    cached_end = "";
    available_start = p.yellow;
    available_mid = "";
    available_end = "";
    used_start = p.red;
    used_mid = "";
    used_end = "";
    download_start = p.orange;
    download_mid = "";
    download_end = "";
    upload_start = p.purple;
    upload_mid = "";
    upload_end = "";
  };
in
{
  programs.btop = {
    enable = true;
    themes.palette = lib.concatStrings (
      lib.mapAttrsToList (name: color: ''
        theme[${name}]="${color}"
      '') theme
    );
    settings = {
      color_theme = "palette";
      vim_keys = true;
    };
  };
}
