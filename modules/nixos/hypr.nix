{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    hypridle
    hyprpolkitagent
  ];

  programs = {
    hyprland.enable = true;
    hyprlock.enable = true;
  };
}
