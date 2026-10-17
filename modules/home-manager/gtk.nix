{
  config,
  lib,
  pkgs,
  ...
}:
let
  p = config.custom.theme.palette;

  # libadwaita's named colors, filled in from custom.theme.palette: views
  # darker than windows, header bars and sidebars a step lighter, popovers and
  # dialogs lighter still. adw-gtk3 styles GTK 3 apps with these names, and
  # GTK 4 apps pick them up through the user CSS below.
  colors = {
    window_bg_color = p.bg0;
    window_fg_color = p.fg0;
    view_bg_color = p.bg_dim;
    view_fg_color = p.fg0;
    headerbar_bg_color = p.bg1;
    headerbar_fg_color = p.fg0;
    headerbar_border_color = p.fg0;
    headerbar_backdrop_color = p.bg0;
    sidebar_bg_color = p.bg1;
    sidebar_fg_color = p.fg0;
    sidebar_backdrop_color = p.bg0;
    secondary_sidebar_bg_color = p.bg0;
    secondary_sidebar_fg_color = p.fg0;
    secondary_sidebar_backdrop_color = p.bg0;
    card_bg_color = p.bg1;
    card_fg_color = p.fg0;
    dialog_bg_color = p.bg_statusline2;
    dialog_fg_color = p.fg0;
    popover_bg_color = p.bg_statusline2;
    popover_fg_color = p.fg0;
    thumbnail_bg_color = p.bg_statusline2;
    thumbnail_fg_color = p.fg0;
    accent_color = p.accent;
    accent_bg_color = p.accent;
    accent_fg_color = p.bg0;
    destructive_color = p.red;
    destructive_bg_color = p.red;
    destructive_fg_color = p.bg0;
    success_color = p.green;
    success_bg_color = p.green;
    success_fg_color = p.bg0;
    warning_color = p.orange;
    warning_bg_color = p.orange;
    warning_fg_color = p.bg0;
    error_color = p.red;
    error_bg_color = p.red;
    error_fg_color = p.bg0;
  };

  # libadwaita's accent presets, used when an app follows the system accent
  accentPresets = {
    blue = p.blue;
    teal = p.aqua;
    green = p.green;
    yellow = p.yellow;
    orange = p.orange;
    red = p.red;
    pink = p.purple;
    purple = p.purple;
    slate = p.grey1;
  };

  namedColors = lib.concatStrings (
    lib.mapAttrsToList (name: color: "@define-color ${name} ${color};\n") colors
  );

  # libadwaita 1.6+ styles through CSS variables (--window-bg-color, ...):
  # point each at its named color, so either mechanism sees the palette.
  cssVariables =
    ":root {\n"
    + lib.concatStrings (
      lib.mapAttrsToList (name: _: "  --${lib.replaceStrings [ "_" ] [ "-" ] name}: @${name};\n") colors
    )
    + lib.concatStrings (
      lib.mapAttrsToList (name: color: "  --accent-${name}: ${color};\n") accentPresets
    )
    + "}\n";
in
{
  dconf.settings = {
    # The system accent, for libadwaita apps that cannot read the user CSS
    # (the sandboxed Flatpaks); everything else gets the palette accent.
    "org/gnome/desktop/interface" = {
      accent-color = "yellow";
    };
    # No minimize/maximize/close buttons in client-side decorations: windows
    # are managed by keybinds, so headerbars keep only the app's own controls.
    # Set here (read via the settings portal) and as gtk-decoration-layout in
    # settings.ini below, since GTK picks one or the other depending on setup.
    "org/gnome/desktop/wm/preferences" = {
      button-layout = ":";
    };
  };

  gtk = {
    enable = true;
    # Dark variants everywhere, including the dconf color-scheme that the
    # settings portal hands to libadwaita, Electron and browsers
    colorScheme = "dark";

    # libadwaita's look for GTK 3 apps, recolored through the named colors
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };

    # Gruvbox icons, with folders in the accent yellow; Qt and rofi use the
    # same theme
    iconTheme = {
      name = "Gruvbox-Plus-Dark";
      package = pkgs.gruvbox-plus-icons.override { folder-color = "yellow"; };
    };

    gtk3 = {
      extraConfig = {
        gtk-decoration-layout = ":";
        gtk-button-images = true;
        gtk-menu-images = true;
      };
      extraCss = namedColors;
    };

    # libadwaita apps keep their own stylesheet (no gtk4.theme import), and
    # only the user CSS recolors them
    gtk4 = {
      theme = null;
      extraConfig = {
        # Plain GTK 4 apps (pavucontrol) take adw-gtk3's GTK 4 style;
        # libadwaita apps ignore this
        gtk-theme-name = "adw-gtk3-dark";
        gtk-decoration-layout = ":";
        gtk-button-images = true;
        gtk-menu-images = true;
      };
      extraCss = namedColors + cssVariables;
    };
  };
}
