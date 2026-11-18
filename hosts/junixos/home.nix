{
  inputs,
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
    ../../modules/zen/profile.nix
  ];

  # Keep the browser's registry location even when adoption is disabled.
  programs.zen-browser.configPath = ".zen";
  custom.desktop.zen.profilePath = "mpjpva0z.default"; # See docs/zen-browser.md before adoption.

  # Custom options
  custom = {
    theme.wallpaper = {
      path = "${inputs.wallpaper}/video/neko-anime-girl-streamer-moewalls-com.mp4";
      backend = "mpvpaper";
    };
    audio.virtualSurround.enable = true;
  };

  home.stateVersion = "24.05";
}
