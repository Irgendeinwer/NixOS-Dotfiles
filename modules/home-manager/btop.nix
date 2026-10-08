{
  programs.btop = {
    enable = true;
    settings = {
      # Theme ships with upstream btop; no vendored theme file needed.
      color_theme = "gruvbox_material_dark";
      vim_keys = true;
    };
  };
}
