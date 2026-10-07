{
  # No home-manager API exists for cava, so this is a literal config file.
  # The input section is intentionally left out: auto-detect already works
  # on PipeWire and an explicit source could break audio capture.
  xdg.configFile."cava/config".text = ''
    [color]
    gradient = 1
    gradient_color_1 = '#b8bb26'
    gradient_color_2 = '#98971a'
    gradient_color_3 = '#d79921'
    gradient_color_4 = '#fabd2f'
    gradient_color_5 = '#fe8019'
    gradient_color_6 = '#fb4934'
    gradient_color_7 = '#cc241d'
    gradient_color_8 = '#9d0006'
  '';
}
