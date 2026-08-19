{
  inputs,
  pkgs,
  ...
}:
{
  home.username = "julian";
  home.homeDirectory = "/home/julian";

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
    # SHELL = "/home/julian/.nix-profile/bin/zsh";
    STEAM_EXTRA_COMPAT_TOOLS_PATH = "~/.steam/root/compatibilitytools.d";
  };

  home.stateVersion = "24.05";

  programs.home-manager.enable = true;
}
