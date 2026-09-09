{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    android-mic
    element-desktop
    vesktop
    zapzap # whatsapp-for-linux
    signal-desktop
    telegram-desktop
  ];
}
