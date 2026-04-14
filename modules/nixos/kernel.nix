{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.kernel;
in
{
  options.kernel = lib.mkOption {
    type = lib.types.enum [ "cachyos" "latest" "lts" ];
    default = "latest";
    description = "The kernel to use.";
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg == "latest") {
      boot.kernelPackages = pkgs.linuxPackages_latest;
    })

    (lib.mkIf (cfg == "lts") {
      boot.kernelPackages = pkgs.linuxPackages;
    })

    (lib.mkIf (cfg == "cachyos") {
      nixpkgs.overlays = [
        inputs.nix-cachyos-kernel.overlays.default
      ];

      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;

      nix.settings = {
        substituters = [
          "https://attic.xuyh0120.win/lantian"
          "https://cache.garnix.io"
        ];
        trusted-public-keys = [
          "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
          "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        ];
      };
    })
  ];
}
