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
		../../modules/home-manager/rofi.nix
	];

	home.packages = with pkgs; [
	];

	gtk = {
		enable = true;
		theme = {
		package = pkgs.gruvbox-gtk-theme;
			name = "gruvbox-gtk-theme";
		};
		iconTheme = {
			package = pkgs.gruvbox-plus-icons;
			name = "Gruvbox-Plus-Dark";
		};
		gtk3.extraConfig = {
                	gtk-application-prefer-dark-theme = true;
                	gtk-button-images = true;
                	gtk-menu-images = true;
            	};

            	gtk4.extraConfig = {
                	gtk-application-prefer-dark-theme = true;
                	gtk-button-images = true;
                	gtk-menu-images = true;
            	};
	};

	qt.enable = true;	

	programs.git = {
		enable = true;
		userName = "Irgendeinwer";
		userEmail = "irgendeinwer@proton.me";
		extraConfig = {
			init.defaultBranch = "main";
		};
	};

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
