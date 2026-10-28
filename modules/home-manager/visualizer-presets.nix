{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  mediaEnabled = if osConfig == null then true else osConfig.custom.desktop.media.enable or false;
  profile =
    if osConfig == null then
      config.custom.desktop.media.royalPresetProfile
    else
      (osConfig.custom.desktop.media.royalPresetProfile or "balanced");
  royalPresetProfiles = import ../../assets/presets/royal-presets.nix { inherit pkgs; };
in
{
  options.custom.desktop.media.royalPresetProfile = lib.mkOption {
    type = lib.types.enum [
      "calm"
      "balanced"
      "intense"
    ];
    default = "balanced";
    description = "Royal Mashup projectM choreography profile.";
  };

  config = lib.mkIf mediaEnabled {
    # Keep the selected static MilkDrop profile in XDG data. The projectM
    # frontend must include this directory in its configured preset search path.
    xdg.dataFile."projectM/presets/Custom/royal-mashup-remix.milk".source =
      "${royalPresetProfiles}/${profile}/royal-mashup-remix.milk";
  };
}
