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

  # Battery and AC notifications (no bar to show the charge level). Needs
  # UPower (custom.system.power.upower); -s skips the burst of notifications
  # at login and -S ignores peripherals such as mouse batteries.
  services.poweralertd = {
    enable = true;
    extraArgs = [
      "-s"
      "-S"
    ];
  };

  home.stateVersion = "24.05";
}
