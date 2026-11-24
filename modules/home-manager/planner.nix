{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  scripts = pkgs.custom or (import ../../pkgs/scripts { inherit lib pkgs; });
  p = config.custom.theme.palette;
  optColor = c: fb: if c != null then c else fb;

  osPlanner = if osConfig != null then (osConfig.custom.desktop.planner or null) else null;
  plannerEnabled =
    if osConfig != null then
      (osPlanner != null && (osPlanner.enable or false))
    else
      config.custom.desktop.planner.enable;

  duxCalendarEnabled =
    plannerEnabled
    && (
      if osPlanner != null then
        (osPlanner.duxCalendar.enable or true)
      else
        config.custom.desktop.planner.duxCalendar.enable
    );

  defaultCaFile = ../../assets + "/junix-ca.pem";
  localCaCert =
    if osConfig != null then
      (
        if (osConfig.custom.system.security.localCa.enable or false) then
          (osConfig.custom.system.security.localCa.certificateFile or null)
        else
          null
      )
    else if builtins.pathExists defaultCaFile then
      defaultCaFile
    else
      null;

  vikunjaUrl =
    if osPlanner != null then
      osPlanner.vikunjaUrl
    else
      "https://tasks.${config.custom.desktop.planner.serverDomain}";

  radicaleUrl =
    if osPlanner != null then
      osPlanner.radicaleUrl
    else
      "https://cal.${config.custom.desktop.planner.serverDomain}";

  radicaleUser = if osPlanner != null then osPlanner.radicaleUser else config.home.username;
  radicaleCalendar =
    if osPlanner != null then
      osPlanner.radicaleCalendar
    else
      config.custom.desktop.planner.radicaleCalendar;
  defaultProject =
    if osPlanner != null then
      osPlanner.defaultProject
    else
      config.custom.desktop.planner.defaultProject;
  timezone = if osPlanner != null then osPlanner.timezone else config.custom.desktop.planner.timezone;
  syncIntervalSec =
    if osPlanner != null then
      osPlanner.syncIntervalSec
    else
      config.custom.desktop.planner.syncIntervalSec;
  autoDnd = if osPlanner != null then osPlanner.autoDnd else config.custom.desktop.planner.autoDnd;
  credentialsFile =
    if osPlanner != null then
      osPlanner.credentialsFile
    else
      config.custom.desktop.planner.credentialsFile;

  # Upstream nixpkgs builds `dux-calendar` with embedded QML (`-tags withshell`)
  # and no bundled `libdux-qt-base.so.0`, so UI supervision requires
  # `DANKCAL_QS_CHILD=1` and `quickshell` (`qs`) on PATH. Strip the static
  # upstream systemd unit so our declarative `systemd.user.services.dcal` owns
  # supervision without unit collisions.
  duxCalendarPkg = pkgs.symlinkJoin {
    name = "dux-calendar-wrapped-${pkgs.dux-calendar.version}";
    paths = [ pkgs.dux-calendar ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm -rf "$out/lib/systemd/user"
      wrapProgram "$out/bin/dcal" \
        --set-default DANKCAL_QS_CHILD 1 \
        --prefix PATH : "${lib.makeBinPath [ pkgs.quickshell ]}"
      rm -f "$out/share/applications/dev.duxlabs.calendar.desktop"
      substitute "${pkgs.dux-calendar}/share/applications/dev.duxlabs.calendar.desktop" \
        "$out/share/applications/dev.duxlabs.calendar.desktop" \
        --replace-fail "Exec=dcal " "Exec=$out/bin/dcal "
    '';
    meta.mainProgram = "dcal";
  };

  dankcalThemePath = "${config.xdg.configHome}/dankcal/gruvbox-theme.json";

  dankcalPaletteBlock = {
    primary = p.accent;
    primaryText = p.bg0;
    primaryContainer = optColor (p.bg_visual_yellow or null) p.bg3;
    onPrimaryContainer = p.fg0;
    secondary = p.orange;
    secondaryContainer = p.bg3;
    onSecondaryContainer = p.fg0;
    tertiary = p.aqua;
    tertiaryContainer = optColor (p.bg_visual_green or null) p.bg3;
    onTertiaryContainer = p.fg0;
    surface = p.bg0;
    surfaceText = p.fg0;
    surfaceVariant = p.bg3;
    surfaceVariantText = p.grey2;
    surfaceTint = p.accent;
    surfaceBright = p.bg5;
    surfaceDim = p.bg_dim;
    background = p.bg0;
    backgroundText = p.fg0;
    outline = p.grey1;
    outlineVariant = p.bg5;
    surfaceContainerLowest = p.bg_dim;
    surfaceContainerLow = p.bg0;
    surfaceContainer = p.bg1;
    surfaceContainerHigh = p.bg3;
    surfaceContainerHighest = p.bg5;
    inverseSurface = p.fg0;
    inverseOnSurface = p.bg0;
    scrim = p.bg_dim;
    error = p.red;
    errorText = p.bg0;
    errorContainer = optColor (p.bg_visual_red or null) p.bg3;
    errorContainerText = p.fg0;
    warning = p.orange;
    info = p.blue;
    success = p.green;
  };

  dankcalDefaultsFile = pkgs.writeText "dankcal-defaults.json" (
    builtins.toJSON {
      themeMode = "dark";
      colorSource = "custom";
      customThemeFile = dankcalThemePath;
      timeFormat = "24h";
      use24HourClock = true;
      firstDayOfWeek = 1;
      showWeekNumbers = true;
      showTasks = true;
    }
  );

  # Enforced on every activation and service start so Dux Calendar never fires
  # duplicate Mako alerts alongside `junix-plan-daemon` and stays bound to the
  # active host palette while keeping `ui-settings.json` writable for UI state
  # (`lastView`, `sidebarWidth`, `dismissedAccountNotices`).
  dankcalEnforcedFile = pkgs.writeText "dankcal-enforced.json" (
    builtins.toJSON {
      remindersEnabled = false;
      allDayReminders = false;
      notificationSounds = false;
      showTrayIcon = false;
      themeMode = "dark";
      colorSource = "custom";
      customThemeFile = dankcalThemePath;
    }
  );

  dankcalSettingsSync = pkgs.writeShellApplication {
    name = "junix-dankcal-settings-sync";
    runtimeInputs = with pkgs; [
      coreutils
      jq
    ];
    text = ''
      cfg_dir="''${XDG_CONFIG_HOME:-${lib.escapeShellArg config.xdg.configHome}}/dankcal"
      cfg_file="$cfg_dir/ui-settings.json"
      install -d -m 0700 "$cfg_dir"

      existing='{}'
      if [ -f "$cfg_file" ] && [ ! -L "$cfg_file" ]; then
        existing="$(jq -ce 'if type == "object" then . else {} end' "$cfg_file" 2>/dev/null || printf '{}')"
      fi

      tmp="$(mktemp "$cfg_dir/.ui-settings.json.XXXXXX")"
      chmod 0600 "$tmp"
      jq -n \
        --slurpfile defaults ${lib.escapeShellArg "${dankcalDefaultsFile}"} \
        --argjson existing "$existing" \
        --slurpfile enforced ${lib.escapeShellArg "${dankcalEnforcedFile}"} \
        '($defaults[0] * $existing * $enforced[0])' > "$tmp"
      [ ! -L "$cfg_file" ] || rm -f "$cfg_file"
      mv -f "$tmp" "$cfg_file"
    '';
  };
in
{
  options.custom.desktop.planner = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the Junix Day Engine in standalone Home Manager evaluations.";
    };

    serverDomain = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "junixsrv.internal";
      description = "Base internal domain hosting Vikunja and Radicale.";
    };

    radicaleCalendar = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "personal";
      description = "Radicale CalDAV collection slug under `<user>/<calendar>/`.";
    };

    defaultProject = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "Inbox";
      description = "Default Vikunja project title used for untagged quick captures.";
    };

    timezone = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "Europe/Berlin";
      description = "IANA timezone used for natural-language capture and day slotting.";
    };

    syncIntervalSec = lib.mkOption {
      type = lib.types.ints.positive;
      default = 180;
      description = "Background sync interval in seconds for `junix-plan-daemon`.";
    };

    autoDnd = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically toggle Mako DND during active Focus steps.";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional environment file setting Vikunja and Radicale credentials.";
    };

    duxCalendar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install and run Dux Calendar (`dcal` + Quickshell UI) themed from
          `custom.theme.palette`, with Dux's built-in reminders disabled so
          `junix-plan-daemon` remains the sole Mako alert source.
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = duxCalendarPkg;
        defaultText = lib.literalExpression "pkgs.dux-calendar /* wrapped with quickshell */";
        readOnly = true;
        internal = true;
        description = "Wrapped `dux-calendar` package exposed to sibling Home Manager modules.";
      };
    };
  };

  config = lib.mkIf plannerEnabled {
    home.packages = [ scripts.plan ] ++ lib.optional duxCalendarEnabled duxCalendarPkg;

    xdg.configFile = {
      "junix-plan/config.json".text = builtins.toJSON {
        vikunja_url = vikunjaUrl;
        radicale_url = radicaleUrl;
        radicale_user = radicaleUser;
        calendar_path = "/${radicaleUser}/${radicaleCalendar}/";
        ca_cert = if localCaCert != null then "${localCaCert}" else "";
        default_project = defaultProject;
        inherit timezone;
        sync_interval_sec = syncIntervalSec;
        auto_dnd = autoDnd;
        credentials_file = if credentialsFile != null then credentialsFile else "";
      };

      "dankcal/gruvbox-theme.json" = lib.mkIf duxCalendarEnabled {
        text = builtins.toJSON {
          dark = dankcalPaletteBlock;
          light = dankcalPaletteBlock;
        };
      };
    };

    home.activation.dankcalSettings = lib.mkIf duxCalendarEnabled (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe dankcalSettingsSync}
      ''
    );

    systemd.user.services = {
      junix-plan-daemon = {
        Unit = {
          Description = "Junix offline-first planner sync, step timer, and reminder daemon";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
          X-Restart-Triggers = [ "${config.xdg.configFile."junix-plan/config.json".source}" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "${scripts.plan}/bin/plan daemon";
          Restart = "on-failure";
          RestartSec = 10;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      dcal = lib.mkIf duxCalendarEnabled {
        Unit = {
          Description = "Dux Calendar (CalDAV UI supervised on Quickshell, alerts delegated to junix-plan-daemon)";
          Documentation = "https://github.com/duxlabs-dev/dux-calendar";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
          StartLimitIntervalSec = 60;
          StartLimitBurst = 5;
          X-Restart-Triggers = [
            "${config.xdg.configFile."dankcal/gruvbox-theme.json".source}"
            "${dankcalSettingsSync}"
          ];
        };
        Service = {
          Type = "simple";
          ExecStartPre = "${lib.getExe dankcalSettingsSync}";
          ExecStart = "${lib.getExe duxCalendarPkg} run --session --hidden";
          Restart = "on-failure";
          RestartSec = 2;
          Slice = "app.slice";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
