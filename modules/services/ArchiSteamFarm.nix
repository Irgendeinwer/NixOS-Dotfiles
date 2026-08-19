{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.archisteamfarm;
in
{
  options.custom.services.archisteamfarm = {
    enable = lib.mkEnableOption "ArchiSteamFarm Steam card farming service";
    webUi = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable ArchiSteamFarm Web UI";
    };
  };

  config = lib.mkIf cfg.enable {
    services.archisteamfarm = {
      enable = true;
      web-ui.enable = cfg.webUi;
    };
  };
}
