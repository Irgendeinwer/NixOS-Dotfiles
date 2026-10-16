{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.hyprland;
in
{
  options.custom.desktop.hyprland = {
    enable = lib.mkEnableOption "Hyprland Wayland compositor";

    monitors = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Declarative monitor configurations for Hyprland.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Run Electron/Chromium apps (Signal, VS Code, ...) as native Wayland
    # clients through the nixpkgs wrappers instead of XWayland.
    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    programs = {
      hyprland.enable = true;
      hyprlock.enable = true;
    };

    # greetd's boot-time auto-login skips the password prompt, so start that
    # session behind hyprlock: Hyprland locks before the first frame, with no
    # flash of the desktop. Logging in through tuigreet stays a single prompt.
    custom.desktop.greetd.initialSessionCommand = lib.mkIf (
      config.custom.desktop.greetd.command == "start-hyprland"
    ) (lib.mkDefault "start-hyprland -- --locked-cmd ${lib.getExe config.programs.hyprlock.package}");
  };
}
