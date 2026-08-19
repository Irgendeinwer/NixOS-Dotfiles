{
  inputs,
  pkgs,
  osConfig,
  ...
}:
let
  user = osConfig.custom.user;
in
{
  home.username = user;
  home.homeDirectory = "/home/${user}";

  imports = [
    ../../modules/home-manager
  ];

  home.packages = with pkgs; [ ];

  qt.enable = true;

  # Custom options
  custom = {
    theme.wallpaper = {
      path = "${inputs.wallpaper}/video/neko-anime-girl-streamer-moewalls-com.mp4";
      backend = "mpvpaper";
    };
    audio.virtualSurround.enable = true;
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    STEAM_EXTRA_COMPAT_TOOLS_PATH = "~/.steam/root/compatibilitytools.d";
  };

  home.stateVersion = "24.05";

  programs.home-manager.enable = true;
}
