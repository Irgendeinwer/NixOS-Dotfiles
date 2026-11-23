{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.desktop.planner;
in
{
  options.custom.desktop.planner = {
    enable = lib.mkEnableOption "offline-first Vikunja + Radicale Day Engine and Hyprland HUD";

    serverDomain = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "junixsrv.internal";
      description = ''
        Base internal domain hosting the Vikunja (`tasks.<domain>`) and
        Radicale (`cal.<domain>`) endpoints.
      '';
    };

    vikunjaUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://tasks.${cfg.serverDomain}";
      defaultText = lib.literalExpression ''"https://tasks.''${serverDomain}"'';
      description = "Base URL of the Vikunja task server.";
    };

    radicaleUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://cal.${cfg.serverDomain}";
      defaultText = lib.literalExpression ''"https://cal.''${serverDomain}"'';
      description = "Base URL of the Radicale CalDAV server.";
    };

    radicaleUser = lib.mkOption {
      type = lib.types.str;
      default = config.custom.user;
      defaultText = lib.literalExpression "config.custom.user";
      description = "Default Radicale principal username.";
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
      default = if (config.time.timeZone or null) != null then config.time.timeZone else "Europe/Berlin";
      defaultText = lib.literalExpression ''config.time.timeZone or "Europe/Berlin"'';
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
      description = ''
        Automatically enable Mako `do-not-disturb` during active Focus steps,
        restoring the prior DND state when the step ends.
      '';
    };

    credentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional path to an environment file setting `VIKUNJA_TOKEN`,
        `RADICALE_USER`, and `RADICALE_PASSWORD` (for example a sops secret
        path). When `null`, `~/.config/junix-plan/credentials.env` written by
        `plan auth` is used.
      '';
    };
  };
}
