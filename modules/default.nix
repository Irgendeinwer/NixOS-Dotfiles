{ lib, ... }:
let
  scanPaths = import ../lib/scan-paths.nix { inherit lib; };
in
{
  imports = (scanPaths ./nixos) ++ (scanPaths ./services) ++ [ ./nixvim/nixvim.nix ];
}
