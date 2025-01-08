{ ... }:
{
  wayland.windowManager.hyprland = {
    enable = true;
    plugins = [];
    systemd.variables = ["--all"];
    settings = {
	exec-once = [
	    "hypridle &"
	    "hyprpaper &"
	    "hyprlock &"
	    "systemctl --user start hyprpolkitagent"
	    
	    "nm-applet --indicator &"
	    "brightnessctl set 100%"

	    "[workspace 10 silent] signal-desktop"
	];
			
	input = {
	    kb_layout = "de";
	    numlock_by_default = false;
			
	    follow_mouse = 2;
	    sensitivity = -0.1; # -1.0 - 1.0, 0 means no modification.
    				
	    touchpad = {
		natural_scroll = false;
	    };
	};
			
	general = {
	    "$mainMod" = "SUPER";

	    gaps_in = 2; # 4
	    gaps_out = 4; # 6
	    border_size = 1; #2

#	    "col.active_border" = "rgb(98971a) rgb(cc241d) 45deg"; # red
	    "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg"; # blue
	    "col.inactive_border" = "rgba(595959aa)";

#	    resize_on_border = true;
#    	    hover_icon_on_border = false;

    	    allow_tearing = false;

	    layout = "dwindle";
	};

	misc = {
	    vfr = true;
	    # key_press_enables_dpms = true;
	    disable_autoreload = true;
	    enable_swallow = true;
	    swallow_regex = "^(kitty)$";
	    new_window_takes_over_fullscreen = 2;
#	    render_unfocused_fps = 25;
	};

	dwindle = {
	    pseudotile = true;
	    smart_split = true;
	};

	decoration = {
	    rounding = 3;
#	    rounding = 5;

	    blur = {
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
	
	    # Time
	    "$mainMod, T, exec, notify-send -t 3000 \"$(date +%H):$(date +%M) Uhr\" \"$(date)\""

	    # Quick access to the bone keyboard layout
	    ",F7, exec, hyprctl keyword input:kb_layout de"
	    ",F8, exec, hyprctl keyword input:kb_layout de\\(bone\\)"

	    # Media and volume controls
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

	gestures = {
	    workspace_swipe = true;
	};

	workspace = [
	    # https://wiki.hyprland.org/Configuring/Workspace-Rules/#smart-gaps Part 1
	    "w[tv1], gapsout:0, gapsin:0"
	    "f[1], gapsout:0, gapsin:0"
	];

	windowrulev2 = [
	    # "idleinhibit fullscreen, class:^(firefox)$"
	    "idleinhibit always, fullscreen:1"
	    "float, title:^(Picture-in-Picture)$"
	    "size 512 288, title:^(Picture-in-Picture)$"
	    "move 2038 40, title:^(Picture-in-Picture)$"
	    "opacity 1.0 override 1.0 override, title:^(Picture-in-Picture)$"
	    "pin, title:^(Picture-in-Picture)$"
	    "noinitialfocus, title:^(Picture-in-Picture)$"

	    "suppressevent maximize, class:.* "

	    # https://wiki.hyprland.org/Configuring/Workspace-Rules/#smart-gaps Part 2
	    "bordersize 0, floating:0, onworkspace:w[tv1]"
	    "rounding 0, floating:0, onworkspace:w[tv1]"
	    "bordersize 0, floating:0, onworkspace:f[1]"
	    "rounding 0, floating:0, onworkspace:f[1]"
	];
    };
    extraConfig = "
	monitor = eDP-1, preferred, auto, 1
	monitor = HDMI-A-1, preferred, 0x0, 1
	";
  };
}
