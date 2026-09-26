{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.system.lix;
in
{
  options.custom.system.lix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use Lix as the default Nix package implementation.";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.package = pkgs.lixPackageSets.stable.lix;
  };
}
