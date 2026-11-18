{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.desktop.hyprland;
  monitorKeys = [
    "output"
    "mode"
    "position"
    "scale"
    "bitdepth"
    "cm"
    "sdrbrightness"
    "hdr"
  ];
  monitorType = lib.types.submodule {
    # Additional metadata can be used by other modules, but the renderer only
    # emits the options listed above. Warn about unused keys below.
    freeformType = lib.types.attrsOf lib.types.anything;
    options = {
      output = lib.mkOption {
        type = lib.types.str;
        description = "Hyprland output name; an empty string matches any output.";
      };
      mode = lib.mkOption {
        type = lib.types.str;
        default = "preferred";
        description = "Resolution and refresh rate, or a Hyprland mode keyword.";
      };
      position = lib.mkOption {
        type = lib.types.str;
        default = "auto";
        description = "Output position, or a Hyprland position keyword.";
      };
      scale = lib.mkOption {
        type = lib.types.numbers.positive;
        default = 1;
        description = "Positive output scale.";
      };
      bitdepth = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Optional output bit depth.";
      };
      cm = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional Hyprland color-management mode.";
      };
      sdrbrightness = lib.mkOption {
        type = lib.types.nullOr lib.types.numbers.nonnegative;
        default = null;
        description = "Optional SDR brightness multiplier.";
      };
      hdr = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Select this output for the HDR toggle.";
      };
    };
  };
  unknownMonitorKeys = lib.unique (
    lib.concatMap (monitor: lib.subtractLists monitorKeys (builtins.attrNames monitor)) cfg.monitors
  );
  hdrMonitors = builtins.filter (monitor: monitor.hdr) cfg.monitors;
in
{
  options.custom.desktop.hyprland = {
    enable = lib.mkEnableOption "Hyprland Wayland compositor";

    monitors = lib.mkOption {
      type = lib.types.listOf monitorType;
      default = [ ];
      description = ''
        Declarative monitor configurations for Hyprland. The renderer emits
        output, mode, position, scale, bitdepth, cm and sdrbrightness. Mark
        one output with hdr = true to select it for the HDR toggle. Extra
        fields are allowed as metadata but are not emitted by the renderer.
      '';
    };

    layerBlur = lib.mkEnableOption "background blur behind desktop layers (launcher, notifications, OSD)";
  };

  config = lib.mkIf cfg.enable {
    warnings =
      lib.optional (unknownMonitorKeys != [ ])
        "custom.desktop.hyprland.monitors: extra fields are not rendered: ${lib.concatStringsSep ", " unknownMonitorKeys}"
      ++ lib.optional (
        builtins.length hdrMonitors > 1
      ) "custom.desktop.hyprland.monitors: multiple HDR outputs are marked; the toggle uses the first.";

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
