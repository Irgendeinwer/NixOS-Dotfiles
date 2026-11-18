{
  config,
  inputs,
  lib,
  osConfig,
  pkgs,
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

  # Adopt the existing Zen profile without replacing its registry or Sync data.
  # See docs/zen-browser.md before the first Home Manager activation.
  programs.zen-browser = {
    configPath = ".zen";
    profiles.default = {
      id = 0;
      isDefault = true;
      path = "mpjpva0z.default";
      settings."browser.aboutConfig.showWarning" = false;
    };
  };
  # The upstream module would otherwise replace profiles.ini with a registry
  # containing only the declared profile, losing the older profile/install
  # entries. Zen continues to own this file.
  home.file."${config.programs.zen-browser.configPath}/profiles.ini".enable = false;

  # Fail before Home Manager writes links if the reported profile disappeared
  # or an unmanaged user.js would otherwise be silently replaced/backed up.
  home.activation.checkExistingZenProfile = import ../../lib/zen-profile-guard.nix {
    inherit config lib pkgs;
    profileName = "default";
  };

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
