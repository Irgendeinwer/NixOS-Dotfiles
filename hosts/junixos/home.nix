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
    (import ../../modules/zen/profile.nix { profilePath = "mpjpva0z.default"; })
  ];

  # The shared Zen configuration adopts this existing profile. See
  # docs/zen-browser.md before switching with the pinned mods for the first time.

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
