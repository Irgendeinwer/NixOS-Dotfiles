{ ... }:
{
  services.hyprpaper = {
    enable = true;
    settings = {
      splash = false; # temp see commit
      splash_offset = 2.0;
      # splash_color = "55ffffff";
      ipc = true;

      preload = [ "~/dotfiles/wallpapers/wallhaven-mdzzj8.jpg" ];

      wallpaper = [ ", ~/dotfiles/wallpapers/wallhaven-mdzzj8.jpg" ];
    };
  };
}
