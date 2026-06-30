final: prev:
let
  lib = prev.lib;

  # If this attribute is removed from nixpkgs, this overlay is no longer needed.
  pnpmAttrExists = prev ? pnpm_10_29_2;
in
{
  pnpm_10_29_2 = lib.throwIf (!pnpmAttrExists) ''
    The pnpm_10_29_2 overlay is no longer needed because the attribute has been removed from nixpkgs.

    See details:
      https://github.com/NixOS/nixpkgs/issues/536623

    You can now safely delete this overlay file.
  '' final.pnpm_10;
}
