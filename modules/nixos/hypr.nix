{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    hyprshot
    hypridle
    xdg-desktop-portal-hyprland
  ];

  programs = {
    hyprland.enable = true;
    hyprlock.enable = true;
  };
}
