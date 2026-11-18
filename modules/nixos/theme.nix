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
    type = import ../theme/palette-type.nix { inherit lib; };
    default = import ../theme/gruvbox-material-mix-dark-medium.nix;
    defaultText = lib.literalExpression "import ./modules/theme/gruvbox-material-mix-dark-medium.nix";
    description = ''
      Color palette shared by every themed program. Home Manager modules read
      it through osConfig, so a different palette here recolors the desktop.
    '';
  };

  config = {
    assertions = [
      {
        assertion = builtins.length palette.ansi == 16;
        message = "custom.theme.palette.ansi must contain exactly 16 colors.";
      }
    ];

    # Linux console colors, which tuigreet's named colors (yellow, green, ...)
    # map onto as well. Color 0 doubles as the console background.
    console.colors = map (lib.removePrefix "#") ([ palette.bg0 ] ++ lib.drop 1 palette.ansi);
  };
}
