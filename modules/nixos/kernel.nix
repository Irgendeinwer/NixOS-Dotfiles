{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.custom.system.kernel;
in
{
  options.custom.system.kernel = lib.mkOption {
    type = lib.types.enum [
      "cachyos"
      "latest"
      "lts"
    ];
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
      boot.kernelPackages =
        inputs.nix-cachyos-kernel.legacyPackages.${pkgs.stdenv.hostPlatform.system}.linuxPackages-cachyos-latest;

      nix.settings = {
        substituters = [ "https://attic.xuyh0120.win/lantian" ];
        trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];
      };
    })
  ];
}
