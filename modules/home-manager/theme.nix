{
  osConfig ? null,
  lib,
  ...
}:
{
  options.custom.theme.palette = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default =
      if osConfig != null && osConfig ? custom.theme.palette then
        osConfig.custom.theme.palette
      else
        import ../theme/gruvbox-material-mix-dark-medium.nix;
    defaultText = lib.literalExpression "osConfig.custom.theme.palette";
    description = "Color palette for themed programs; follows the NixOS palette.";
  };
}
