{ ... }:
{
  services.hyprpaper = {
    enable = true;
    settings = {
	splash = false; #temp see commit
	splash_offset = 2.0;
	# splash_color = "55ffffff";
	ipc = true;

	preload = [ "~/dotfiles/wallpapers/plague_tale_arthur-57vpr5.jpg" ];

	wallpaper = [
	    ", ~/dotfiles/wallpapers/plague_tale_arthur-57vpr5.jpg"
	];
    };
  };
}
