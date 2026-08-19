{ lib, ... }:
let
  # Recursively find all .nix files in this directory, ignoring default.nix
  scanPaths =
    dir:
    let
      entries = builtins.readDir dir;
      processEntry =
        name: type:
        let
          path = dir + "/${name}";
        in
        if type == "directory" then
          scanPaths path
        else if type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix" then
          [ path ]
        else
          [ ];
    in
    lib.flatten (lib.mapAttrsToList processEntry entries);
in
{
  imports = scanPaths ./.;
}
