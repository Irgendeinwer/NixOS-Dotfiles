{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.theme.wallpaper;

  # Binary references using Nix Best Practices
  hyprctl   = getExe' pkgs.hyprland "hyprctl";
  mpvpaper  = getExe pkgs.mpvpaper;
  socat     = getExe pkgs.socat;
  jq        = getExe pkgs.jq;

  # mpvpaper control socket
  mpvSocket = "${config.home.homeDirectory}/.cache/mpvpaper-ipc.sock";

  mpvFlags = [
    "--no-audio"
    "--loop"
    "--hwdec=auto-safe"
    "--vo=gpu"
    "--profile=fast"
    "--input-ipc-server=${mpvSocket}"
    "--no-osc"
    "--no-osd-bar"
  ];
in {
  options.theme.wallpaper = {
    path = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to the wallpaper file (image or video)";
    };
    backend = mkOption {
      type = types.enum [ "hyprpaper" "mpvpaper" ];
      default = "hyprpaper";
      description = "hyprpaper for static images, mpvpaper for video loops.";
    };
  };

  config = mkIf (cfg.path != null) (mkMerge [
    
    # 1. Hyprpaper (Static / Laptop)
    (mkIf (cfg.backend == "hyprpaper") {
      services.hyprpaper = {
        enable = true;
        settings = {
          splash = false;
          ipc = "on";
          preload = [ "${cfg.path}" ];
          wallpaper = [
            {
              monitor = ""; # Empty string = all monitors
              path = "${cfg.path}";
            }
          ];
        };
      };
    })

    # 2. Mpvpaper (Video / Desktop)
    (mkIf (cfg.backend == "mpvpaper") {
      systemd.user.services.mpvpaper = {
        Unit = {
          Description = "mpvpaper video wallpaper daemon";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
          ConditionPathExists = "${cfg.path}";
        };
        Service = {
          ExecStart = "${mpvpaper} -o '${concatStringsSep " " mpvFlags}' '*' ${cfg.path}";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      systemd.user.services.mpvpaper-autopause = {
        Unit = {
          Description = "Instant event-based auto-pause for mpvpaper";
          After = [ "mpvpaper.service" ];
          PartOf = [ "mpvpaper.service" ];
        };
        Service = {
          ExecStart = pkgs.writeShellScript "mpvpaper-autopause" ''
            LAST_STATE="unknown"
            MPV_SOCK="${mpvSocket}"

            update_state() {
              # Safety check: ensure the mpv socket exists
              if [ ! -S "$MPV_SOCK" ]; then return; fi

              WINDOWS=$(${hyprctl} activeworkspace -j | ${jq} '.windows')
              
              if [ "$WINDOWS" -gt 0 ] && [ "$LAST_STATE" != "paused" ]; then
                echo '{"command": ["set_property", "pause", true]}' | ${socat} - UNIX-CONNECT:"$MPV_SOCK" >/dev/null 2>&1 || true
                LAST_STATE="paused"
              elif [ "$WINDOWS" -eq 0 ] && [ "$LAST_STATE" != "playing" ]; then
                echo '{"command": ["set_property", "pause", false]}' | ${socat} - UNIX-CONNECT:"$MPV_SOCK" >/dev/null 2>&1 || true
                LAST_STATE="playing"
              fi
            }

            while true; do
              # Dynamically find the Hyprland socket signature
              HYPR_SIG=$(ls -t "$XDG_RUNTIME_DIR/hypr/" 2>/dev/null | head -n 1)
              HYPR_SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPR_SIG/.socket2.sock"

              # Wait for both sockets to exist before starting the listener
              if [ ! -S "$HYPR_SOCKET" ] || [ ! -S "$MPV_SOCK" ]; then
                sleep 2
                continue
              fi

              # Initial state sync on start or resume
              update_state

              # Listen to Hyprland events
              ${socat} -u UNIX-CONNECT:"$HYPR_SOCKET" | while read -r line; do
                case "$line" in
                  openwindow*|closewindow*|workspace*|movewindow*)
                    update_state
                    ;;
                esac
              done
              
              # If the pipe breaks (e.g. suspend/resume), wait and retry the loop
              sleep 1
            done
          '';
          Restart = "always";
          RestartSec = "3";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })
  ]);
}
