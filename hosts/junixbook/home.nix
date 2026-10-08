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

  # Custom options
  custom.theme.wallpaper = {
    path = "${inputs.wallpaper}/image/wallhaven-gwq117.jpg";
    backend = "hyprpaper";
  };

  home.stateVersion = "24.05";
}
