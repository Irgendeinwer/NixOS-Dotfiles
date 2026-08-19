{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.printing;
in
{
  options.custom.services.printing = {
    enable = lib.mkEnableOption "CUPS printing service and Avahi mDNS discovery";
  };

  config = lib.mkIf cfg.enable {
    services.printing.enable = true;

    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
  };
}
