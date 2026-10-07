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
  ];

  qt.enable = true;

  # Custom options
  custom.theme.wallpaper = {
    path = "${inputs.wallpaper}/image/wallhaven-gwq117.jpg";
    backend = "hyprpaper";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  home.stateVersion = "24.05";

  programs.home-manager.enable = true;
}
