{
  config,
  inputs ? { },
  lib,
  osConfig ? null,
  pkgs,
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

  missnixPkg =
    if pkgs ? missnix then
      pkgs.missnix
    else if inputs ? missnix then
      inputs.missnix.packages.${pkgs.stdenv.hostPlatform.system}.default
    else
      throw "custom.desktop.missnix requires `inputs.missnix` or `pkgs.missnix`.";

  accentHexUpper = lib.toUpper p.accent;
  validAccent = builtins.match "#[0-9A-F]{6}" accentHexUpper != null;
  safeAccentHex = if validAccent then accentHexUpper else "#E9B143";

  seedSql = ''
    PRAGMA busy_timeout = 5000;
    INSERT OR IGNORE INTO settings (key, value) VALUES
      ('dark_mode', 'true'),
      ('accent_preset', '7'),
      ('custom_accent_hex', '${safeAccentHex}');
  '';

  missnixSeedHelper = pkgs.writeShellApplication {
    name = "junix-missnix-seed";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.sqlite
      missnixPkg
    ];
    text = ''
      db_dir="''${XDG_DATA_HOME:-${lib.escapeShellArg config.xdg.dataHome}}/missnix"
      db_file="''${MISSNIX_DB_PATH:-$db_dir/missnix.db}"
      if [ ! -f "$db_file" ]; then
        missnix --status >/dev/null
      fi
      if [ -f "$db_file" ]; then
        sqlite3 "$db_file" ${lib.escapeShellArg seedSql}
      fi
    '';
  };

  missnixCheckScript = pkgs.writeShellApplication {
    name = "junix-missnix-check";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.libnotify
      pkgs.sqlite
      missnixPkg
    ];
    text = ''
      ${lib.optionalString seedPaletteAccent ''
        ${lib.getExe missnixSeedHelper}
      ''}
      music_dirs=(${lib.escapeShellArgs musicDirs})
      args=()
      for dir in "''${music_dirs[@]}"; do
        if [ -d "$dir" ]; then
          args+=(--scan "$dir")
        fi
      done
      args+=(--check --status)

      out="$(missnix "''${args[@]}")"
      printf '%s\n' "$out"

      ${lib.optionalString notifyNewReleases ''
        new_added="$(printf '%s\n' "$out" | sed -n 's/.*checked, \([0-9][0-9]*\) new releases added.*/\1/p' | tail -n 1)"
        unseen_total="$(printf '%s\n' "$out" | sed -n 's/.*(\([0-9][0-9]*\) unseen new drops).*/\1/p' | tail -n 1)"
        if [ -n "$new_added" ] && [ "$new_added" -gt 0 ]; then
          body="''${new_added} new release(s) discovered"
          if [ -n "$unseen_total" ]; then
            body="''${body} (''${unseen_total} unseen total)"
          fi
          notify-send -a MissNix -i missnix "MissNix Release Radar" "$body" || true
        fi
      ''}
    '';
  };
in
{
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
      description = "Seed MissNix's SQLite settings with dark mode and `custom.theme.palette.accent` on first creation.";
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
        description = "Send a desktop Mako notification when new releases are discovered.";
      };
    };
  };

  config = lib.mkIf missnixEnabled {
    home.packages = [ missnixPkg ];

    home.activation.missnixSeedTheme = lib.mkIf seedPaletteAccent (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe missnixSeedHelper} || true
      ''
    );

    systemd.user.services.missnix-check = lib.mkIf timerEnabled {
      Unit = {
        Description = "MissNix headless local music scan and new-release radar check";
        Documentation = "https://github.com/Irgendeinwer/MissNix";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${lib.getExe missnixCheckScript}";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.user.timers.missnix-check = lib.mkIf timerEnabled {
      Unit = {
        Description = "Run MissNix headless release check once a day";
        Documentation = "https://github.com/Irgendeinwer/MissNix";
      };
      Timer = {
        OnCalendar = timerOnCalendar;
        Persistent = true;
        RandomizedDelaySec = timerRandomizedDelaySec;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
