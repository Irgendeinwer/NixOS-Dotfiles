{ config, pkgs, ... }:
{
wayland.windowManager.hyprland = {
		enable = true;
		plugins = [];
		systemd.variables = ["--all"];
		settings = {
			exec-once = [
				"hypridle &"
				"hyprpaper &"
				# "swww-daemon &"
				# "swww img ~/dotfiles/wallpapers/bg-noflash.webp &"
				"waybar &"
				"hyprlock &"
				"brightnessctl set 100%"
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

			#	"col.active_border" = "rgb(98971a) rgb(cc241d) 45deg"; # red
    				"col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg"; # blue
    				"col.inactive_border" = "rgba(595959aa)";

    				resize_on_border = true;
    				hover_icon_on_border = false;

    				allow_tearing = false;

    				layout = "dwindle";
			};

			misc = {
				vfr = true;
				# key_press_enables_dpms = true;
				disable_autoreload = true;
				enable_swallow = true;
				new_window_takes_over_fullscreen = 2;
			#	render_unfocused_fps = 25;
			};

			dwindle = {
				pseudotile = true;
				smart_split = true;
				no_gaps_when_only = 1;
			};

			decoration = {
				rounding = 3;
			#	rounding = 5;

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

				# Media and volume controls
				",F9, exec, pamixer -d 5"
				",F10, exec, pamixer -i 5"
				",XF86AudioRaiseVolume, exec, pamixer -i 5"
				",XF86AudioLowerVolume, exec, pamixer -d 5"
				",XF86AudioMute, exec, pamixer -t"
				",XF86AudioPlay, exec, playerctl play-pause"
				",XF86AudioNext, exec, playerctl next"
				",XF86AudioPrev, exec, playerctl previous"
				",XF86AudioStop, exec, playerctl stop"
				",XF86AudioMicMute, exec, pamixer --default-source -t"

				",XF86MonBrightnessUp, exec, brightnessctl set 5%+"
				",XF86MonBrightnessDown, exec, brightnessctl set 5%-"

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

			windowrulev2 = [
				"idleinhibit fullscreen, class:^(firefox)$"

				"float, title:^(Picture-in-Picture)$"
				"size 512 288, title:^(Picture-in-Picture)$"
				"move 2038 40, title:^(Picture-in-Picture)$"
				"opacity 1.0 override 1.0 override, title:^(Picture-in-Picture)$"
				"pin, title:^(Picture-in-Picture)$"
				"noinitialfocus, title:^(Picture-in-Picture)$"

				"suppressevent maximize, class:.* "
			];
		};
		extraConfig = "
			monitor = eDP-1, preferred, auto, 1
			monitor = HDMI-A-1, preferred, 0x0, 1
		";
	};
}

# See https://wiki.hyprland.org/Configuring/Environment-variables/
/*
env = XCURSOR_SIZE,60
env = HYPRCURSOR_SIZE,40
*/
/*
animations {
    enabled = true

    # Default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more

    bezier = myBezier, 0.05, 0.9, 0.1, 1.05

    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = borderangle, 1, 8, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}
*/
