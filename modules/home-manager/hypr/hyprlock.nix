{ config, pkgs, ...}:
{
  programs.hyprlock = {
	enable = true;
	settings = {
		general = {
			disable_loading_bar = false;
			hide_cursor = false; # buggy?
			# grace = 3;
			no_fade_in = false;
			no_fade_out = false;
			ignore_empty_input = true;
			immediate_render = true;
		};

		background = [
	  	  {
			path = "~/dotfiles/wallpapers/jellyfish-space-k9v8d1.png";
			blur_passes = 0;
			blur_size = 0;
	    	  }
		];

		label = [
		  {
			monitor = "";
    			text = "    Julian Lindner, 10a";
			text_align = "center";
			color = "rgba(216, 222, 233, 0.80)";
			font_size = 36;
			font_family = "Noto Nerd Font Bold";
			
			position = "0, -180";
			halign = "center";
			valign = "center";
		  }
		  # Time
		  {
			monitor = "";
			text = "$TIME";
			text_align = "center";
			color = "rgba(216, 222, 233, .7)";
			font_size = 180;
			font_family = "Fira Code Nerd Fontadasdasd";

			position = "0, 370";
			halign = "center";
			valign = "center";
		  }
		];

		input-field = [
  	  	  {
		  	monitor = "";
      			size = "300, 60";
			outline_thickness = 2;
      			dots_size = 0.2;
			dots_spacing = 0.2;
			dots_center = true;
      			outer_color = "rgba(255, 255, 255, 0)";
			inner_color = "rgba(255, 255, 255, 0.3)";
			font_color = "rgb(200, 200, 200)";
			fade_on_empty = true;
			# font_family = "Noto Nerd Font Bold";
			placeholder_text =
			''<i><span foreground="##ffffff99">🔒 Enter Password</span></i>'';
			shadow_passes = 0;
			shadow_size = 0;

			position = "0, 0";
			halign = "center";
			valign = "center";
    	  	  }
  		];
	};
  };
}
