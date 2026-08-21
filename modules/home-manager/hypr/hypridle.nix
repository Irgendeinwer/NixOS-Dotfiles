{ pkgs, ... }:
let
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
  hyprlock = "${pkgs.hyprlock}/bin/hyprlock";
  loginctl = "${pkgs.systemd}/bin/loginctl";
in
{
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "${hyprctl} keyword input:kb_layout de; pidof hyprlock || ${hyprlock}";

        before_sleep_cmd = "${loginctl} lock-session";

        after_sleep_cmd = "${hyprctl} dispatch dpms on";
      };

      # Empty: disables all idle auto-locks and timeouts
      listener = [ ];
    };
  };
}
