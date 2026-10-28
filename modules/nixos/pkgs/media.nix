{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.media;
  royalPresetProfiles = import ../../../assets/presets/royal-presets.nix { inherit pkgs; };
  feishinForProfile = pkgs.feishin.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      presetDir=src/renderer/features/visualizer/components/butternchurn
      # Make the unpacked source writable and replace any stale read-only copy.
      chmod -R u+w "$presetDir"
      rm -f "$presetDir/royal-mashup-remix.ts"
      cp ${royalPresetProfiles}/${cfg.royalPresetProfile}/royal-mashup-remix.butterchurn.ts \
        "$presetDir/royal-mashup-remix.ts"
    '';
  });
in
{
  options.custom.desktop.media = {
    enable = lib.mkEnableOption "desktop media players and media tools";

    royalPresetProfile = lib.mkOption {
      type = lib.types.enum [
        "calm"
        "balanced"
        "intense"
      ];
      default = "balanced";
      description = "Royal Mashup visualizer choreography profile.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      mediainfo
      pear-desktop
      celluloid
      vlc
      feishinForProfile
      rush-lyrics
      imv
      projectm-sdl-cpp
      audacity
    ];
  };
}
