{ config, pkgs, ... }:
{
  services.hyprpaper = {
	enable = true;
	settings = {
		splash = true;
		splash_offset = 2.0;
		# splash_color = "55ffffff";
		ipc = true;

		preload = [ "~/dotfiles/wallpapers/gruvbox_pixel.png" ];

		wallpaper = [
			", ~/dotfiles/wallpapers/gruvbox_pixel.png"
		];
	};
  };
}
