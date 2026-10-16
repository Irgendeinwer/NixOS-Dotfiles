{ config, ... }:
let
  p = config.custom.theme.palette;
in
{
  # Declarative notification daemon, themed from custom.theme.palette.
  # Started on demand via D-Bus activation.
  services.mako = {
    enable = true;

    settings = {
      font = "monospace 11";
      # Show above fullscreen windows (the default "top" layer hides under
      # them): without a bar, notifications are the main status surface.
      layer = "overlay";
      # Slightly translucent, so the desktop's layer blur turns the
      # notifications frosted glass (on the laptop it is just a hint)
      background-color = "${p.bg1}f2";
      text-color = p.fg0;
      border-size = 2;
      border-color = p.accent;
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
        border-color = p.grey1;
        default-timeout = 4000;
      };

      "urgency=high" = {
        border-color = p.red;
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
