{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.desktop.greetd;
  gettyCfg = config.custom.desktop.getty;

  tuigreetCmd = lib.concatStringsSep " " [
    "${pkgs.tuigreet}/bin/tuigreet"
    "--time"
    "--time-format '%A, %d %B %Y - %H:%M'"
    "--remember"
    "--remember-user-session"
    "--asterisks"
    "--asterisks-char '•'"
    "--greeting 'Welcome back!'"
    "--theme 'border=cyan;text=white;prompt=green;time=magenta;action=blue;button=yellow'"
    "--window-padding 2"
    "--container-padding 3"
    "--power-shutdown 'systemctl poweroff'"
    "--power-reboot 'systemctl reboot'"
    "--cmd ${cfg.command}"
  ];
in
{
  options.custom.desktop = {
    greetd = {
      enable = lib.mkEnableOption "greetd display manager";
      command = lib.mkOption {
        type = lib.types.str;
        default = "start-hyprland";
        description = "Command or wrapper to launch the desktop session.";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = config.custom.user;
        description = "User to start the initial session for.";
      };
    };

    getty = {
      enable = lib.mkEnableOption "getty auto-login on TTY";
      user = lib.mkOption {
        type = lib.types.str;
        default = config.custom.user;
        description = "User to auto-login to a bare TTY shell.";
      };
    };
  };

  config = lib.mkMerge [
    # Guard against enabling both display manager and bare TTY auto-login on the same host
    {
      assertions = [
        {
          assertion = !(cfg.enable && gettyCfg.enable);
          message = "Cannot enable both custom.desktop.greetd and custom.desktop.getty on the same host.";
        }
      ];
    }

    # Greetd Configuration
    (lib.mkIf cfg.enable {
      services.greetd = {
        enable = true;
        settings = {
          # Boot: Auto-login into configured command (e.g. Hyprland)
          initial_session = {
            command = "${cfg.command}";
            user = cfg.user;
          };

          # Logout Fallback: Clean, riced tuigreet TUI
          default_session = {
            command = tuigreetCmd;
            user = "greeter";
          };
        };
      };
    })

    # Bare Getty Fallback (e.g. for headless/server profiles)
    (lib.mkIf gettyCfg.enable {
      services.getty.autologinUser = gettyCfg.user;
    })
  ];
}
