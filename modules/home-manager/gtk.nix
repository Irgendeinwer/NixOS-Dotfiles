{ pkgs, ... }:
{
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
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

    theme = {
      name = "gruvbox-dark-gtk";
      package = pkgs.gruvbox-dark-gtk;
    };

    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-decoration-layout = ":";
      gtk-button-images = true;
      gtk-menu-images = true;
    };

    gtk4 = {
      theme = null;
      extraConfig = {
        gtk-application-prefer-dark-theme = true;
        gtk-decoration-layout = ":";
        gtk-button-images = true;
        gtk-menu-images = true;
      };
    };
  };
}
