{ config, pkgs, ...}:
{
  programs.hyprlock = {
	enable = true;
	settings = {
		general = {
			disable_loading_bar = false;
			hide_cursor = true;
			grace = 0;
			no_fade_in = false;
			no_fade_out = false;
			ignore_empty_input = true;
			immediate_render = false;
			fractional_scaling = 2;
		};

		background = [
	  	  {
			path = "~/wallpapers/nix-glow-black.png";
			blur_passes = 4;
			blur_size = 3;
	    	  }
		];

		label = [
		  {
			monitor = "";
    			text = "    $USER";
			text_align = "center";
			color = "rgba(216, 222, 233, 0.80)";
			outline_thickness = 2;
			dots_size = 0.2;
			dots_spacing = 0.2;
			dots_center = true;
			font_size = 18;
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
			font_family = "Fira Code Nerd Font";

			position = "0, 370";
			halign = "center";
			valign = "center";
		  }
		];

		input-field = [
  	  	  {
      			size = "225, 75";
      			position = "0, 0";
			text = "xyz: $ATTEMPTS";
			text_align = "right";
      			monitor = "";
      			dots_center = true;
      			fade_on_empty = true;
      			font_color = "rgb(202, 211, 245)";
      			inner_color = "rgb(91, 96, 120)";
      			outer_color = "rgb(24, 25, 38)";
      			outline_thickness = 5;
      			placeholder_text = "Try: UwU";
      			shadow_passes = 5;
			shadow_size = 3;
    	  	  }
  		];
	};
  };
}
