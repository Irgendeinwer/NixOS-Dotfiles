{
  # Declarative notification daemon (gruvbox). Started on demand via D-Bus
  # activation; replaces the previous mako/dunst provider ambiguity.
  services.mako = {
    enable = true;

    settings = {
      font = "monospace 11";
      # Show above fullscreen windows (the default "top" layer hides under
      # them): without a bar, notifications are the main status surface.
      layer = "overlay";
      background-color = "#282828";
      text-color = "#ebdbb2";
      border-size = 2;
      border-color = "#d79921";
      border-radius = 8;
      padding = 10;
      margin = 10;
      width = 350;
      max-visible = 5;
      default-timeout = 5000;
      icons = true;
      max-icon-size = 48;
      markup = true;
      actions = true;
      format = "<b>%s</b>\\n%b";

      "urgency=low" = {
        border-color = "#928374";
        default-timeout = 4000;
      };

      "urgency=high" = {
        border-color = "#fb4934";
        default-timeout = 0;
      };

      # Do not disturb (SUPER+N, `makoctl mode -t do-not-disturb`): hide all
      # notifications except critical ones and those you trigger yourself
      # through notify-send keybinds, like the clock on SUPER+T.
      "mode=do-not-disturb" = {
        invisible = 1;
      };
      "mode=do-not-disturb app-name=notify-send" = {
        invisible = 0;
      };
      "mode=do-not-disturb urgency=critical" = {
        invisible = 0;
      };
    };
  };
}
