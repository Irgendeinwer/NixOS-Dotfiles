{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.system.security.localCa;
  defaultCaFile = ../../assets + "/junix-ca.pem";
in
{
  options.custom.system.security.localCa = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Trust the repository's private Root CA (`assets/junix-ca.pem` when
        present) in the system certificate bundle so internal HTTPS services
        validate without browser or CLI warnings.
      '';
    };

    certificateFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = if builtins.pathExists defaultCaFile then defaultCaFile else null;
      defaultText = lib.literalExpression "../../assets/junix-ca.pem (if present)";
      description = ''
        Public PEM certificate for the private Root CA. Defaults to
        `assets/junix-ca.pem` once generated; `null` leaves the system CA
        bundle unchanged.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.certificateFile != null) {
    security.pki.certificateFiles = [ cfg.certificateFile ];
  };
}
