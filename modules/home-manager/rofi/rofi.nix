{ pkgs, ... }:
{
  programs.rofi = {
	enable = true;
	package = pkgs.rofi-wayland;
	location = "center";
	theme = "~/dotfiles/modules/home-manager/rofi/gruvbox-material.rasi";
  };
}
