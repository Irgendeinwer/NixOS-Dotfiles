final: prev:
let
  lib = prev.lib;

  plugin = prev.obs-studio-plugins.obs-move-transition or null;
  # Once nixpkgs updates past 3.2.1, this overlay can likely be removed.
  isFixedVersion = plugin != null && lib.versionAtLeast (plugin.version or "0") "3.3.0";
in
{
  obs-studio-plugins = prev.obs-studio-plugins // {
    obs-move-transition =
      lib.warnIf isFixedVersion
        ''
          The obs-move-transition overlay may no longer be needed because the package version is >= 3.3.0.
          You can test removing this overlay file.
        ''
        (
          prev.obs-studio-plugins.obs-move-transition.overrideAttrs (oldAttrs: {
            NIX_CFLAGS_COMPILE = (oldAttrs.NIX_CFLAGS_COMPILE or "") + " -Wno-error=deprecated-declarations";
          })
        );
  };
}
