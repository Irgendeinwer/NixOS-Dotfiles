{
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  # Same gate as hyprland.nix: skip when another compositor is in use
  hyprlandEnabled =
    if osConfig != null then (osConfig.custom.desktop.hyprland.enable or false) else true;
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
  hyprlock = "${pkgs.hyprlock}/bin/hyprlock";
  loginctl = "${pkgs.systemd}/bin/loginctl";

  # Hyprland runs a Lua config: `hyprctl keyword` is rejected and `hyprctl
  # dispatch` evaluates its argument as a Lua dispatcher expression. Wrapped in
  # a script so hypridle's own config parser never sees the Lua braces.
  dpmsOn = pkgs.writeShellScript "hypr-dpms-on" ''
    exec ${hyprctl} dispatch 'hl.dsp.dpms({ action = "on" })'
  '';
in
{
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || ${hyprlock}";

        before_sleep_cmd = "${loginctl} lock-session";

        after_sleep_cmd = "${dpmsOn}";
      };

      # Empty: disables all idle auto-locks and timeouts
      listener = [ ];
    };
  };
}
