{ lib, osConfig ? null, ... }:
let
  mediaEnabled =
    if osConfig == null then
      true
    else
      osConfig.custom.desktop.media.enable or false;
in
{
  # Keep the custom MilkDrop preset in XDG data. The projectM frontend must
  # include this directory in its configured preset search path.
  xdg.dataFile = lib.mkIf mediaEnabled {
    "projectM/presets/Custom/royal-mashup-remix.milk".source =
      ../../assets/presets/royal-mashup-remix.milk;
  };
}
