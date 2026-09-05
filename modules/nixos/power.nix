{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.system.power;
in
{
  options.custom.system.power = {
    suspendThenHibernate = {
      enable = lib.mkEnableOption "Suspend-then-hibernate after a configured timeout (clears RAM keys to encrypted swap)";

      hibernateDelaySec = lib.mkOption {
        type = lib.types.int;
        default = 3600;
        description = "Time in seconds to wait in suspend before hibernating to disk (default: 3600s = 1 hour).";
      };
    };
  };

  config = lib.mkIf cfg.suspendThenHibernate.enable {
    systemd.sleep.settings.Sleep = {
      HibernateDelaySec = "${toString cfg.suspendThenHibernate.hibernateDelaySec}s";
    };

    services.logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandleLidSwitchExternalPower = "suspend-then-hibernate";
    };
  };
}
