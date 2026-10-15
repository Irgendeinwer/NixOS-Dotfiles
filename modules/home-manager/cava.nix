{ config, ... }:
let
  p = config.custom.theme.palette;
in
{
  # No home-manager API exists for cava, so this is a literal config file.
  # The input section is intentionally left out: auto-detect already works
  # on PipeWire and an explicit source could break audio capture.
  # cava reads gradient colors up to the first unset one (at most 7).
  xdg.configFile."cava/config".text = ''
    [color]
    gradient = 1
    gradient_color_1 = '${p.aqua}'
    gradient_color_2 = '${p.green}'
    gradient_color_3 = '${p.yellow}'
    gradient_color_4 = '${p.orange}'
    gradient_color_5 = '${p.red}'
  '';
}
