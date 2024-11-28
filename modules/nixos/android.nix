{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    scrcpy
  ];
  virtualisation.waydroid.enable = true;
}
