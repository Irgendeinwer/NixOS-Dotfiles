{
  lib,
  pkgs,
}:
let
  # Fixed-output fetches happen during the Nix build, never during activation.
  # The JSON keeps those store paths in its dependency closure.
  mods = builtins.fromJSON (builtins.readFile ./mods.json);
  resolved = map (mod: {
    inherit (mod) entry;
    files = lib.mapAttrs (
      _: file:
      file
      // {
        source = toString (
          pkgs.fetchurl {
            inherit (file) url sha256;
          }
        );
      }
    ) mod.files;
  }) mods;
in
pkgs.writeText "zen-pinned-mods.json" (builtins.toJSON resolved)
