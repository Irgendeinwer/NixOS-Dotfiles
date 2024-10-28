{ config, pkgs, ... }:
{
	home.username = "julian";
	home.homeDirectory = "/home/julian";

	imports = [
		../../modules/home-manager/hypr/hyprland.nix
		../../modules/home-manager/hypr/hyprpaper.nix
		../../modules/home-manager/hypr/hyprlock.nix
		../../modules/home-manager/hypr/hypridle.nix
		../../modules/home-manager/zsh.nix
		../../modules/home-manager/git.nix
		../../modules/home-manager/rofi/rofi.nix
		../../modules/home-manager/gtk.nix
	];

	home.packages = with pkgs; [
	];
	
	qt.enable = true;
		
	services.kdeconnect.enable = true;
	services.kdeconnect.indicator = true;

	home.sessionVariables = {
		EDITOR = "nvim";
		# SHELL = "/home/julian/.nix-profile/bin/zsh";
		STEAM_EXTRA_COMPAT_TOOLS_PATH = "~/.steam/root/compatibilitytools.d";
	};

	home.stateVersion = "24.05";

	programs.home-manager.enable = true;
}
