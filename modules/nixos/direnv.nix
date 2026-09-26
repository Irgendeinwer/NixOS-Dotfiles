{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.system.direnv;
in
{
  options.custom.system.direnv = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable direnv and nix-direnv shell integration.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.direnv = {
      enable = true;
      silent = false;
      loadInNixShell = true;
      direnvrcExtra = "";
      nix-direnv = {
        enable = true;
        package = pkgs.nix-direnv;
      };
    };
  };
}
