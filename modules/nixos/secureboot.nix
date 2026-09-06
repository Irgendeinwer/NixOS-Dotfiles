{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.system.boot.secureboot;
in
{
  options.custom.system.boot.secureboot = {
    enable = lib.mkEnableOption "UEFI Secure Boot using Lanzaboote";

    pkiBundle = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/sbctl";
      description = "Directory where Secure Boot keys and database certificates are stored.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install sbctl for key generation, verification, and enrollment
    environment.systemPackages = [ pkgs.sbctl ];

    # Lanzaboote provides its own signed systemd-boot loader implementation
    boot.loader.systemd-boot.enable = lib.mkForce false;

    boot.lanzaboote = {
      enable = true;
      pkiBundle = cfg.pkiBundle;
    };
  };
}
