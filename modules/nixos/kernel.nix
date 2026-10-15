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
      # Built locally, without the maintainer's binary cache: its server was
      # compromised in October 2026 (xddxdd/nix-cachyos-kernel#110), so its
      # signing key is no longer trusted. Only add a cache back once it
      # returns with a new key.
      boot.kernelPackages =
        inputs.nix-cachyos-kernel.legacyPackages.${pkgs.stdenv.hostPlatform.system}.linuxPackages-cachyos-bore-lto-x86_64-v3;
    })
  ];
}
