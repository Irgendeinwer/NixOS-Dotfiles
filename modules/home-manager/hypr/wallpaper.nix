{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.theme.wallpaper;

  # Binary references
  hyprctl   = getExe' pkgs.hyprland "hyprctl";
  mpvpaper  = getExe pkgs.mpvpaper;
  socat     = getExe pkgs.socat;
  jq        = getExe pkgs.jq;

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
    
    # ----------------------------------------------------
    # BACKEND: Hyprpaper (Static / Laptop)
    # ----------------------------------------------------
    (mkIf (cfg.backend == "hyprpaper") {
      services.hyprpaper = {
        enable = true;
        settings = {
          splash = false;
          ipc = "on";
          preload = [ "${cfg.path}" ];
          # Use the object syntax for better compatibility with 0.8.x
          wallpaper = [
            {
              monitor = ""; # Empty string = all monitors
              path = "${cfg.path}";
            }
          ];
        };
      };
    })

    # ----------------------------------------------------
    # BACKEND: Mpvpaper (Video / Desktop)
    # ----------------------------------------------------
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
            update_state() {
              WINDOWS=$(${hyprctl} activeworkspace -j | ${jq} '.windows')
              if [ "$WINDOWS" -gt 0 ] && [ "$LAST_STATE" != "paused" ]; then
                echo '{"command": ["set_property", "pause", true]}' | ${socat} - UNIX-CONNECT:"${mpvSocket}" >/dev/null 2>&1 || true
                LAST_STATE="paused"
              elif [ "$WINDOWS" -eq 0 ] && [ "$LAST_STATE" != "playing" ]; then
                echo '{"command": ["set_property", "pause", false]}' | ${socat} - UNIX-CONNECT:"${mpvSocket}" >/dev/null 2>&1 || true
                LAST_STATE="playing"
              fi
            }
            while true; do
              HYPR_SIG=$(ls -t "$XDG_RUNTIME_DIR/hypr/" 2>/dev/null | head -n 1)
              HYPR_SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPR_SIG/.socket2.sock"
              if [ ! -S "$HYPR_SOCKET" ] || [ ! -S "${mpvSocket}" ]; then
                sleep 2
                continue
              fi
              update_state
              ${socat} -u UNIX-CONNECT:"$HYPR_SOCKET" | while read -r line; do
                case "$line" in
                  openwindow*|closewindow*|workspace*|movewindow*)
                    update_state
                    ;;
                esac
              done
              sleep 1
            done
          '';
          Restart = "always";
          RestartSec = "2";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })
  ]);
}
