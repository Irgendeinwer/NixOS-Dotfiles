final: prev:
let
  lib = prev.lib;

  electron40Exists = prev ? electron_40;
in
{
  vesktop =
    lib.throwIf (!electron40Exists)
      ''
        The vesktop overlay is no longer needed because electron_40 has been removed from nixpkgs.
        Upstream vesktop has migrated to a newer Electron version.

        You can now safely delete this overlay file.
      ''
      (
        (prev.vesktop.override {
          electron_40 = final.electron_42;
        }).overrideAttrs
          (old: {
            preBuild = builtins.replaceStrings [ "exit 1" ] [ ":" ] (old.preBuild or "");
          })
      );
}
