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

  # Approximate a truecolor value in the fixed xterm 256-color cube or grey
  # ramp. Avoid slots 0-15: terminals are free to redefine those colors.
  cterm =
    color:
    let
      c = channels color;
      squareDistance =
        a: b:
        let
          d = a - b;
        in
        d * d;
      steps = [
        0
        95
        135
        175
        215
        255
      ];
      nearestStep =
        value:
        lib.foldl' (
          best: candidate:
          if
            squareDistance value (builtins.elemAt steps candidate)
            < squareDistance value (builtins.elemAt steps best)
          then
            candidate
          else
            best
        ) 0 (lib.range 1 5);
      r = nearestStep c.r;
      g = nearestStep c.g;
      b = nearestStep c.b;
      cubeDistance =
        squareDistance c.r (builtins.elemAt steps r)
        + squareDistance c.g (builtins.elemAt steps g)
        + squareDistance c.b (builtins.elemAt steps b);
      greyDistance =
        i:
        let
          value = 8 + 10 * i;
        in
        squareDistance c.r value + squareDistance c.g value + squareDistance c.b value;
      grey = lib.foldl' (
        best: candidate: if greyDistance candidate < greyDistance best then candidate else best
      ) 0 (lib.range 1 23);
    in
    if cubeDistance <= greyDistance grey then 16 + 36 * r + 6 * g + b else 232 + grey;

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
