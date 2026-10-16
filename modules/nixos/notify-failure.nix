{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Template service that units opt into with
  #   unitConfig.OnFailure = [ "notify-failure@%N.service" ];
  # to get a desktop notification when they fail. Critical urgency, so
  # mako shows it even in do-not-disturb mode. Only makes sense with a
  # graphical session, so it follows the desktop toggle; where the
  # template does not exist, OnFailure is ignored by systemd.
  config = lib.mkIf config.custom.desktop.hyprland.enable {
    systemd.services."notify-failure@" = {
      description = "Desktop notification about the failed unit %i";
      serviceConfig = {
        Type = "oneshot";
        User = config.custom.user;
        ExecStart = "${lib.getExe pkgs.libnotify} -u critical -a systemd \"Unit failed: %i\" \"See: journalctl -u %i\"";
      };
    };
  };
}
