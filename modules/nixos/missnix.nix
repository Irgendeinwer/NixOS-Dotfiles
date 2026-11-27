{
  config,
  lib,
  ...
}:
{
  options.custom.desktop.missnix = {
    enable = lib.mkEnableOption "MissNix local music release radar GUI and daily background check";

    musicDirs = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ "/home/${config.custom.user}/music" ];
      defaultText = lib.literalExpression ''[ "/home/''${config.custom.user}/music" ]'';
      description = ''
        Local music library folders scanned headlessly (`--scan <dir>`) before
        checking Deezer and MusicBrainz for new releases. Non-existent folders
        are skipped gracefully until synced.
      '';
    };

    seedPaletteAccent = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Seed MissNix's SQLite `settings` table with dark mode and
        `custom.theme.palette.accent` (`accent_preset = 7`) on first creation,
        preserving any subsequent theme changes made in the UI.
      '';
    };

    timer = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run a daily headless `missnix --check` systemd user timer
          (`Persistent = true`) so missed checks while powered off catch up
          automatically after the next login.
        '';
      };

      onCalendar = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "daily";
        description = "Systemd `OnCalendar` schedule for the headless release check.";
      };

      randomizedDelaySec = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "20m";
        description = "Random jitter added to `missnix-check.timer` to avoid boot/login spikes.";
      };

      notifyNewReleases = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Send a desktop Mako notification (`notify-send`) when a scheduled
          headless check discovers new releases.
        '';
      };
    };
  };
}
