{
  config,
  lib,
  ...
}:
{
  options.custom.desktop = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.custom.desktop.wayland.enable;
      defaultText = lib.literalExpression "config.custom.desktop.wayland.enable";
      description = ''
        Enable the shared graphical desktop baseline, independently of the
        compositor. By default it follows the shared Wayland baseline.
      '';
    };

    wayland.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.custom.desktop.hyprland.enable;
      defaultText = lib.literalExpression "config.custom.desktop.hyprland.enable";
      description = ''
        Enable shared Wayland tools and user services (including mako, which
        needs layer-shell support). This does not select a compositor; it
        defaults to on when Hyprland is enabled.
      '';
    };
  };
}
