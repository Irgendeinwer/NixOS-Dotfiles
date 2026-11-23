{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  scripts = pkgs.custom or (import ../../pkgs/scripts { inherit lib pkgs; });

  osPlanner = if osConfig != null then (osConfig.custom.desktop.planner or null) else null;
  plannerEnabled =
    if osConfig != null then
      (osPlanner != null && (osPlanner.enable or false))
    else
      config.custom.desktop.planner.enable;

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
  };

  config = lib.mkIf plannerEnabled {
    home.packages = [ scripts.plan ];

    xdg.configFile."junix-plan/config.json".text = builtins.toJSON {
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

    systemd.user.services.junix-plan-daemon = {
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
  };
}
