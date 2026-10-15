{
  config,
  lib,
  ...
}:
let
  palette = config.custom.theme.palette;
in
{
  options.custom.theme.palette = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = import ../theme/gruvbox-material-mix-dark-medium.nix;
    defaultText = lib.literalExpression "import ./modules/theme/gruvbox-material-mix-dark-medium.nix";
    description = ''
      Color palette shared by every themed program. Home Manager modules read
      it through osConfig, so a different palette here recolors the desktop.
    '';
  };

  # Linux console colors, which tuigreet's named colors (yellow, green, ...)
  # map onto as well. Color 0 doubles as the console background.
  config.console.colors = map (lib.removePrefix "#") ([ palette.bg0 ] ++ lib.drop 1 palette.ansi);
}
