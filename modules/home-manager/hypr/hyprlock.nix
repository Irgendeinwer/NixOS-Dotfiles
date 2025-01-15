{ ...}:
{
  programs.hyprlock = {
    enable = true;
    settings = {
	general = {
	    disable_loading_bar = false;
	    hide_cursor = true; # buggy?
	    # grace = 3;
	    no_fade_in = false;
	    no_fade_out = false;
	    ignore_empty_input = true;
	    immediate_render = false;
	};

	background = [
	  {
	    path = "~/dotfiles/wallpapers/nix-flake-gruvbox.png";
	    blur_passes = 0;
	    blur_size = 0;
	  }
	];

	label = [
	  {
	    monitor = "";
	    text = "     Julian";
	    text_align = "center";
	    color = "rgba(255, 255, 255, 0.90)";
	    font_size = 36;
	    font_family = "Noto Nerd Font Bold";
			
	    position = "0, -300";
	    halign = "center";
	    valign = "center";
	  }
	# Time
	  {
	    monitor = "";
	    text = "$TIME";
	    text_align = "center";
	    color = "rgba(255, 255, 255, 0.90)";
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
	    size = "200, 60";
	    outline_thickness = 2;
	    dots_size = 0.2;
	    dots_spacing = 0.2;
	    dots_center = true;
	    outer_color = "rgba(55, 55, 55, 0)";
	    inner_color = "rgba(55, 55, 55, 0.3)";
	    font_color = "rgb(200, 200, 200)";
	    fade_on_empty = true;
	    # font_family = "Noto Nerd Font Bold";
	    placeholder_text =
	    ''<i><span foreground="##ffffff99">Welcome!</span></i>'';
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
