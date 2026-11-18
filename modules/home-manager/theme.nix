{
  config,
  osConfig ? null,
  lib,
  ...
}:
{
  options.custom.theme.palette = lib.mkOption {
    type = import ../theme/palette-type.nix { inherit lib; };
    default =
      if osConfig != null && osConfig ? custom.theme.palette then
        osConfig.custom.theme.palette
      else
        import ../theme/gruvbox-material-mix-dark-medium.nix;
    defaultText = lib.literalExpression "osConfig.custom.theme.palette";
    description = "Color palette for themed programs; follows the NixOS palette.";
  };

  config.assertions = [
    {
      assertion = builtins.length config.custom.theme.palette.ansi == 16;
      message = "custom.theme.palette.ansi must contain exactly 16 colors.";
    }
  ];
}
