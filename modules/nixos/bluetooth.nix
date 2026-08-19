{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.hardware.bluetooth;
in
{
  options.custom.hardware.bluetooth = {
    enable = lib.mkEnableOption "Bluetooth support and Blueman manager";
  };

  config = lib.mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    services.blueman.enable = true;
  };
}
