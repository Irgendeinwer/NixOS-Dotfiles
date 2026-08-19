{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.immich;
in
{
  options.custom.services.immich = {
    enable = lib.mkEnableOption "Immich photo and video management solution";
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports for Immich";
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Host interface to bind Immich to";
    };
    mediaLocation = lib.mkOption {
      type = lib.types.str;
      default = "/media/fun/gallery";
      description = "Path to store Immich media files";
    };
  };

  config = lib.mkIf cfg.enable {
    services.immich = {
      enable = true;
      openFirewall = cfg.openFirewall;
      host = cfg.host;
      mediaLocation = cfg.mediaLocation;
    };
  };
}
