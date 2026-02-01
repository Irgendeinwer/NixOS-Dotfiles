{ ... }:
{
  wayland.windowManager.hyprland = {
    enable = true;
    plugins = [ ];
    systemd.enable = true;
    systemd.variables = [ "--all" ];
    settings = {
      "$mainMod" = "SUPER";
      exec-once = [
        "hypridle"
        "hyprpaper"
        "hyprlock"
        "systemctl --user start hyprpolkitagent"

	"wl-paste --type text --watch cliphist store"
	"wl-paste --type image --watch cliphist store"

        "nm-applet --indicator"
        "brightnessctl set 100%"

        "[workspace 10 silent] signal-desktop"
	"[workspace 10 silent] easyeffects"
      ];

      input = {
        kb_layout = "de";
        numlock_by_default = false;

        follow_mouse = 2;
        sensitivity = 0;
        accel_profile = "flat";

        touchpad = {
          natural_scroll = false;
          disable_while_typing = false;
        };
      };

      gesture = [
	"3, horizontal, workspace"
      ];

      general = {

        gaps_in = 2;
        gaps_out = 4;
        border_size = 1;

        "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg"; # blue
        "col.inactive_border" = "rgba(595959aa)";

        allow_tearing = false;

        layout = "dwindle";
      };

      misc = {
        vfr = true;
        vrr = 3;
        key_press_enables_dpms = true;
        disable_autoreload = true;

	force_default_wallpaper = 0;
        disable_hyprland_logo = true;

        enable_swallow = true;
        swallow_regex = "^(kitty)$";
      };

      dwindle = {
        pseudotile = true;
        smart_split = true;
      };

      decoration = {
        rounding = 3;

        blur = {
          enabled = false;
        };

	shadow = {
	  enabled = false;
	};
      };

      animations = {
        enabled = true;
      };

      bind = [
        "$mainMod, Q, exec, kitty"
        "$mainMod, W, exec, rofi -show drun -show-icons"
        "$mainMod, D, killactive,"
        "$mainMod, M, exit,"
        "$mainMod, F, togglefloating,"
        "$mainMod, J, togglesplit,"

        "$mainMod, Escape, exec, loginctl lock-session"
        ",PRINT, exec, hyprshot -m region --freeze"

	# Clipboard history
	"$mainMod, V, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy"

        # Peace and tranquility
        "$mainMod, Y, exec, xdg-open https://www.youtube.com/watch?v=Eni9PPPPBpg"

        # Time
        ''$mainMod, T, exec, notify-send -t 3000 "$(date +%H):$(date +%M) Uhr" "$(date)"''

        # Quick access to the bone keyboard layout
        # ",F7, exec, hyprctl keyword input:kb_layout de"
        # ",F8, exec, hyprctl keyword input:kb_layout de\\(bone\\)"

        # Media and volume controls
	",F8, exec, playerctl play-pause"
        ",F9, exec, pamixer -d 2"
        ",F10, exec, pamixer -i 2"

        ",XF86AudioRaiseVolume, exec, pamixer -i 2"
        ",XF86AudioLowerVolume, exec, pamixer -d 2"
        ",XF86AudioMute, exec, pamixer -t"
        ",XF86AudioPlay, exec, playerctl play-pause"
        ",XF86AudioNext, exec, playerctl next"
        ",XF86AudioPrev, exec, playerctl previous"
        ",XF86AudioStop, exec, playerctl stop"
        ",XF86AudioMicMute, exec, pamixer --default-source -t"
        ",XF86MonBrightnessUp, exec, brightnessctl set 10%+"
        ",XF86MonBrightnessDown, exec, brightnessctl set 10%-"

        # switch focus
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"

        # switch workspace
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"
        "$mainMod, 0, workspace, 10"

        # move window
        "$mainMod SHIFT, 1, movetoworkspacesilent, 1"
        "$mainMod SHIFT, 2, movetoworkspacesilent, 2"
        "$mainMod SHIFT, 3, movetoworkspacesilent, 3"
        "$mainMod SHIFT, 4, movetoworkspacesilent, 4"
        "$mainMod SHIFT, 5, movetoworkspacesilent, 5"
        "$mainMod SHIFT, 6, movetoworkspacesilent, 6"
        "$mainMod SHIFT, 7, movetoworkspacesilent, 7"
        "$mainMod SHIFT, 8, movetoworkspacesilent, 8"
        "$mainMod SHIFT, 9, movetoworkspacesilent, 9"
        "$mainMod SHIFT, 0, movetoworkspacesilent, 10"

        "$mainMod, S, togglespecialworkspace, magic"
        "$mainMod SHIFT, S, movetoworkspace, special:magic"
        "$mainMod, mouse_down, workspace, e-1"
        "$mainMod, mouse_up, workspace, e+1"

        # window control
        "$mainMod SHIFT, left, movewindow, l"
        "$mainMod SHIFT, right, movewindow, r"
        "$mainMod SHIFT, up, movewindow, u"
        "$mainMod SHIFT, down, movewindow, d"
        "$mainMod CTRL, left, resizeactive, -40 0"
        "$mainMod CTRL, right, resizeactive, 40 0"
        "$mainMod CTRL, up, resizeactive, 0 -40"
        "$mainMod CTRL, down, resizeactive, 0 40"
        "$mainMod ALT, left, moveactive,  -40 0"
        "$mainMod ALT, right, moveactive, 40 0"
        "$mainMod ALT, up, moveactive, 0 -40"
        "$mainMod ALT, down, moveactive, 0 40"
      ];

      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

      cursor = {
        hide_on_key_press = true;
      };

      workspace = [
        # Only gap settings belong here. 
        # Border/rounding settings must be in windowrule.
        "w[t1], gapsout:0, gapsin:0"
        "f[1], gapsout:0, gapsin:0"
      ];

      windowrule = [
        # --- Picture-in-Picture ---
        "float 1, match:title ^(Picture-in-Picture)$"
        "pin 1, match:title ^(Picture-in-Picture)$"
        "move 2038 10, match:title ^(Picture-in-Picture)$"
        "size 512 288, match:title ^(Picture-in-Picture)$"
        "no_initial_focus 1, match:title ^(Picture-in-Picture)$"
        "opacity 1.0 override 1.0 override, match:title ^(Picture-in-Picture)$"

        # --- General ---
        "suppress_event maximize, match:class .*"

        # --- Smart Gaps ---
        "border_size 0, match:workspace w[t1]"
        "rounding 0, match:workspace w[t1]"
        
        "border_size 0, match:workspace f[1]"
        "rounding 0, match:workspace f[1]"
      ];
    };
    extraConfig = "\n	monitor = eDP-1, preferred, auto, 1\n	monitor = HDMI-A-1, preferred, 0x0, 1\n	";
  };
}
