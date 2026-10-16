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

    # Build the Lix-adjacent tooling against Lix's Nix too. This used to
    # be a global overlay, applied even with Lix switched off.
    nixpkgs.overlays = [
      (final: prev: {
        inherit (prev.lixPackageSets.stable)
          nixpkgs-review
          nix-eval-jobs
          nix-fast-build
          colmena
          ;
      })
    ];
  };
}
