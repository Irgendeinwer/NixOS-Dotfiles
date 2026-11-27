{
  config,
  inputs,
  lib,
  osConfig ? null,
  ...
}:
let
  p = config.custom.theme.palette;
  osMissnix = if osConfig != null then (osConfig.custom.desktop.missnix or null) else null;

  missnixEnabled =
    if osConfig != null then
      (osMissnix != null && (osMissnix.enable or false))
    else
      config.custom.desktop.missnix.enable;

  musicDirs =
    if osMissnix != null then osMissnix.musicDirs else config.custom.desktop.missnix.musicDirs;

  seedPaletteAccent =
    if osMissnix != null then
      osMissnix.seedPaletteAccent
    else
      config.custom.desktop.missnix.seedPaletteAccent;

  timerEnabled =
    if osMissnix != null then osMissnix.timer.enable else config.custom.desktop.missnix.timer.enable;

  timerOnCalendar =
    if osMissnix != null then
      osMissnix.timer.onCalendar
    else
      config.custom.desktop.missnix.timer.onCalendar;

  timerRandomizedDelaySec =
    if osMissnix != null then
      osMissnix.timer.randomizedDelaySec
    else
      config.custom.desktop.missnix.timer.randomizedDelaySec;

  notifyNewReleases =
    if osMissnix != null then
      osMissnix.timer.notifyNewReleases
    else
      config.custom.desktop.missnix.timer.notifyNewReleases;

  accentHexUpper = lib.toUpper p.accent;
  validAccent = builtins.match "#[0-9A-F]{6}" accentHexUpper != null;
  safeAccentHex = if validAccent then accentHexUpper else "#E9B143";
in
{
  imports = [ inputs.missnix.homeManagerModules.default ];

  options.custom.desktop.missnix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable MissNix and its daily headless check in standalone Home Manager evaluations.";
    };

    musicDirs = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ "${config.home.homeDirectory}/music" ];
      defaultText = lib.literalExpression ''[ "''${config.home.homeDirectory}/music" ]'';
      description = "Local music library folders scanned headlessly before checking releases.";
    };

    seedPaletteAccent = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Set MissNix's initial dark mode and `custom.theme.palette.accent` defaults via `MISSNIX_DEFAULT_*`.";
    };

    timer = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the daily headless `missnix --check` systemd user timer.";
      };

      onCalendar = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "daily";
        description = "Systemd `OnCalendar` schedule for `missnix-check.timer`.";
      };

      randomizedDelaySec = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "20m";
        description = "Random jitter added to `missnix-check.timer`.";
      };

      notifyNewReleases = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Pass `--notify` so new releases trigger a desktop Mako notification.";
      };
    };
  };

  config.programs.missnix = {
    enable = lib.mkDefault missnixEnabled;
    musicDirs = lib.mkDefault musicDirs;
    defaultDarkMode = lib.mkDefault (if seedPaletteAccent then true else null);
    defaultAccentHex = lib.mkDefault (if seedPaletteAccent then safeAccentHex else null);
    timer = {
      enable = lib.mkDefault timerEnabled;
      onCalendar = lib.mkDefault timerOnCalendar;
      persistent = lib.mkDefault true;
      randomizedDelaySec = lib.mkDefault timerRandomizedDelaySec;
      notify = lib.mkDefault notifyNewReleases;
    };
  };
}
