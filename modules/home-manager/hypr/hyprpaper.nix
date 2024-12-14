{ ... }:
{
  services.hyprpaper = {
    enable = true;
    settings = {
	splash = true;
	splash_offset = 2.0;
	# splash_color = "55ffffff";
	ipc = true;

	preload = [ "~/dotfiles/wallpapers/Witcher_IV_Wallpaper_01_13840x2160_EN.jpeg" ];

	wallpaper = [
	    ", ~/dotfiles/wallpapers/Witcher_IV_Wallpaper_01_13840x2160_EN.jpeg"
	];
    };
  };
}
