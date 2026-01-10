{ config, pkgs, ... }:
{
  # 1. Keep the service enabled so the systemd unit is created
  services.hyprpaper.enable = true;

  # 2. Add the package to your path (helps with manual debugging)
  home.packages = [ pkgs.hyprpaper ];

  # 3. Manually write the config file in the new 0.8.x block format
  # This avoids the "key = value" limitation of the HM module
  xdg.configFile."hypr/hyprpaper.conf".text = ''
    splash = false
    ipc = true

    preload = ${config.home.homeDirectory}/dotfiles/wallpapers/wallhaven-mdzzj8.jpg

    wallpaper {
        monitor =
        path = ${config.home.homeDirectory}/dotfiles/wallpapers/wallhaven-mdzzj8.jpg
    }
  '';

  # 4. Clear the module's default settings so they don't conflict
  services.hyprpaper.settings = {};
}
