{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.services.openrgb;
in
{
  options.custom.services.openrgb = {
    enable = lib.mkEnableOption "OpenRGB hardware lighting control service";
  };

  config = lib.mkIf cfg.enable {
    services.hardware.openrgb = {
      enable = true;
      package = pkgs.openrgb-with-all-plugins;
    };
  };
}
