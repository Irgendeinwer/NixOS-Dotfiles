# Format helpers for palette colors ("#rrggbb" strings).
# Usage: themeLib = import ../theme/lib.nix { inherit lib; };
{ lib }:
rec {
  # "#d8a657" -> "d8a657"
  hex = color: lib.removePrefix "#" color;

  # "#d8a657" -> { r = 216; g = 166; b = 87; }
  channels =
    color:
    let
      h = hex color;
      channel = i: lib.fromHexString (builtins.substring i 2 h);
    in
    {
      r = channel 0;
      g = channel 2;
      b = channel 4;
    };

  # "#d8a657" -> "rgb(216, 166, 87)"
  rgb =
    color:
    let
      c = channels color;
    in
    "rgb(${toString c.r}, ${toString c.g}, ${toString c.b})";

  # "#d8a657" "0.75" -> "rgba(216, 166, 87, 0.75)" (alpha as a string)
  rgba =
    color: alpha:
    let
      c = channels color;
    in
    "rgba(${toString c.r}, ${toString c.g}, ${toString c.b}, ${alpha})";
}
