{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.jellyfin;
in
{
  options.custom.services.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin media server";
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports for Jellyfin";
    };
  };

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      openFirewall = cfg.openFirewall;
    };
  };
}
