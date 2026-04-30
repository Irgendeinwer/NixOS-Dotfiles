final: prev:
let
  lib = prev.lib;

  brokenVersion = "2.6.13";
  currentVersion = prev.openldap.version;
in
{
  openldap =
    lib.throwIf (currentVersion != brokenVersion)
      ''
        The openldap overlay is pinned to openldap ${brokenVersion} but nixpkgs now ships ${currentVersion}.

        Re-check whether the i686 test-suite workaround is still required:
          https://github.com/NixOS/nixpkgs/issues/513245
          https://github.com/NixOS/nixpkgs/pull/429119

        If upstream has shipped the fix → delete this overlay.
        If not → bump `brokenVersion` in this file to ${currentVersion}.
      ''
      (
        prev.openldap.overrideAttrs (old: {
          doCheck = !prev.stdenv.hostPlatform.isi686;
        })
      );
}
