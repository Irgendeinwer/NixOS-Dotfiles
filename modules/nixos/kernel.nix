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
        inputs.nix-cachyos-kernel.legacyPackages.${pkgs.stdenv.hostPlatform.system}.linuxPackages-cachyos-bore-lto-x86_64-v3;

      # The maintainer's cache returned under a new URL and signing key after
      # the October 2026 server compromise (xddxdd/nix-cachyos-kernel#110),
      # where the old private key was stolen. Only the new key is trusted, so
      # anything signed with the old one is rejected. cache.nixos.org stays
      # available, since nixpkgs appends it to these lists itself.
      nix.settings = {
        substituters = [ "https://cache.lantian.pub/lantian" ];
        trusted-public-keys = [ "lantian:WVGO7vsRMSEN+h7Lp7kv6SAmrkEXgUGbbXm7jMDjBuQ=" ];
      };
    })
  ];
}
