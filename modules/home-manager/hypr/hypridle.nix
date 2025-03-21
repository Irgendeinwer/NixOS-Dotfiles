{ ... }:
{
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "hyprctl keyword input:kb_layout de && pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      /*
        		listener = [
        		  {
        			timeout = 150; # 2.5 min
        			on-timeout = "brightnessctl -s set 10";
        			on-resume = "brightnessctl -r";
        		  }
        		  {
        			timeout = 150; # 2.5min.
        			on-timeout = "brightnessctl -sd dell::kbd_backlight set 0";
        			on-resume = "brightnessctl -rd dell::kbd_backlight";
        		  }
        		  {
        			timeout = 290;
        			on-timeout = "notify-send 'Lock in 10 seconds!'";
        		  }
        		  {
        			timeout = 300; # 5 min
        			on-timeout = "loginctl lock-session";
        		  }
        		  {
        			timeout = 330; # 5.5 min
        			on-timeout = "hyprctl dispatch dpms off";
        			on-resume = "hyprctl dispatch dpms on";
        		  }
        		  {
        			timeout = 900; # 15 min
        			on-timeout = "systemctl suspend";
        		  }
        		];
      */
    };
  };
}
