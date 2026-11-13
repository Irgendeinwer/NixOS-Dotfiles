{ config, lib, ... }:

let
  cfg = config.custom.hardware.xbox-controller;
in
{
  options.custom.hardware.xbox-controller = {
    enable = lib.mkEnableOption "xone driver for wired and dongle Xbox One/Series controllers";
    disableLed = lib.mkEnableOption "disabling the Xbox Guide button LED via udev";
  };

  config = lib.mkIf cfg.enable {
    hardware.xone.enable = true;

    services.udev.extraRules = lib.mkIf cfg.disableLed ''
      ACTION=="add|change", SUBSYSTEM=="leds", KERNEL=="gip*", ATTR{mode}="0", ATTR{brightness}="0"
    '';
  };
}
