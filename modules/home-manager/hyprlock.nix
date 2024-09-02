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
			ignore_empty_input = false;
			immediate_render = false;
			fractional_scaling = 2;
		};

		background = [
	  	  {
			path = "~/wallpapers/nix-glow-black.png";
	    	  }
		];

		input-field = [
  	  	  {
      			size = "200, 100";
      			position = "0, 0";
      			monitor = "";
      			dots_center = true;
      			fade_on_empty = true;
      			font_color = "rgb(202, 211, 245)";
      			inner_color = "rgb(91, 96, 120)";
      			outer_color = "rgb(24, 25, 38)";
      			outline_thickness = 5;
      			placeholder_text = "Enter Secret UwU";
      			shadow_passes = 2;
    	  	  }
  		];
	};
  };
}
