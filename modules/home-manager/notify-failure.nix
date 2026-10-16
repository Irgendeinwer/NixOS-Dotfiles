{ pkgs, ... }:
{
  # User-scope twin of modules/nixos/notify-failure.nix: user units opt
  # in with Unit.OnFailure = [ "notify-failure@%N.service" ] to get a
  # critical desktop notification when they fail (critical shows even
  # in mako's do-not-disturb mode).
  systemd.user.services."notify-failure@" = {
    Unit.Description = "Desktop notification about the failed user unit %i";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.libnotify}/bin/notify-send -u critical -a systemd \"Unit failed: %i\" \"See: journalctl --user -u %i\"";
    };
  };
}
