{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.system.nh;
in
{
  options.custom.system.nh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable nh Nix helper with automatic garbage collection.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 8d --keep 6";
      flake = "/home/${config.custom.user}/dotfiles";
    };
  };
}
