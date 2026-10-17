{
  config,
  lib,
  pkgs,
  ...
}:
let
  p = config.custom.theme.palette;
  inherit (import ../theme/lib.nix { inherit lib; }) hex;

  # QPalette color roles, in the order qt5ct/qt6ct read them. With exactly
  # these 21 entries, Qt 6.6+ derives the Accent role from Highlight.
  roles = [
    "WindowText"
    "Button"
    "Light"
    "Midlight"
    "Dark"
    "Mid"
    "Text"
    "BrightText"
    "ButtonText"
    "Base"
    "Window"
    "Shadow"
    "Highlight"
    "HighlightedText"
    "Link"
    "LinkVisited"
    "AlternateBase"
    "NoRole"
    "ToolTipBase"
    "ToolTipText"
    "PlaceholderText"
  ];

  # Same surfaces as the GTK theme (gtk.nix): input fields and lists (Base)
  # darker than windows, selections and links in the accent color.
  active = {
    WindowText = p.fg0;
    Button = p.bg1;
    Light = p.grey0;
    Midlight = p.bg5;
    Dark = p.bg_dim;
    Mid = p.bg3;
    Text = p.fg0;
    BrightText = p.fg1;
    ButtonText = p.fg0;
    Base = p.bg_dim;
    Window = p.bg0;
    Shadow = p.bg_dim;
    Highlight = p.accent;
    HighlightedText = p.bg0;
    Link = p.accent;
    LinkVisited = p.purple;
    AlternateBase = p.bg0;
    NoRole = p.bg0;
    ToolTipBase = p.bg1;
    ToolTipText = p.fg0;
    PlaceholderText = p.grey1;
  };

  disabled = active // {
    WindowText = p.grey0;
    Text = p.grey0;
    ButtonText = p.grey0;
    Highlight = p.bg3;
    HighlightedText = p.grey1;
  };

  colorList = colors: lib.concatMapStringsSep ", " (role: "#ff${hex colors.${role}}") roles;

  colorScheme = pkgs.writeText "qtct-palette.conf" ''
    [ColorScheme]
    active_colors=${colorList active}
    inactive_colors=${colorList active}
    disabled_colors=${colorList disabled}
  '';

  # qt5ct (Qt 5 apps) and qt6ct (Qt 6 apps) share these settings: the
  # Fusion style with the palette above and the GTK icon theme. Fonts stay
  # at Qt's defaults.
  qtctSettings = {
    Appearance = {
      style = "Fusion";
      custom_palette = true;
      color_scheme_path = "${colorScheme}";
    }
    // lib.optionalAttrs (config.gtk.iconTheme != null) {
      icon_theme = config.gtk.iconTheme.name;
    };
  };
in
{
  qt = {
    # mkDefault, so a host can still turn Qt theming off entirely
    enable = lib.mkDefault true;
    # QT_QPA_PLATFORMTHEME=qt5ct, which qt6ct answers to as well
    platformTheme.name = "qtct";
    qt5ctSettings = qtctSettings;
    qt6ctSettings = qtctSettings;
  };
}
