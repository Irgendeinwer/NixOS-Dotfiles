{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    hyprshot
    hypridle
    hyprpolkitagent
  ];

  programs = {
    hyprland.enable = true;
    hyprlock.enable = true;
  };
}
