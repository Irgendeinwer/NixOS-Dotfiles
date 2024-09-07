{ config, pkgs, ... }:
{
	home.username = "julian";
	home.homeDirectory = "/home/julian";

	imports = [
		../../modules/home-manager/hypr/hyprland.nix
		../../modules/home-manager/hypr/hyprpaper.nix
		../../modules/home-manager/hypr/hyprlock.nix
		../../modules/home-manager/hypr/hypridle.nix
	];

	home.packages = with pkgs; [
	];

	gtk = {
		enable = true;
		theme.name = "adw-gtk3-dark";
	};
	
	programs.zsh = {
  		enable = true;
  		enableCompletion = true;
  		autosuggestion.enable = true;
  		syntaxHighlighting.enable = true;

		shellAliases = {
			config = "cd ~/dotfiles/ && nvim hosts/junixbook/configuration.nix";
			hardware-config = "cd ~/dotfiles/ && nvim hosts/junixbook/hardware-configuration.nix";
			flake = "cd ~/dotfiles/ && nvim flake.nix";
			home = "cd ~/dotfiles/ && nvim hosts/junixbook/home.nix";
			hypr = "cd ~/dotfiles/ && nvim modules/home-manager/hypr/";

			rebuild = "~/dotfiles/modules/scripts/rebuild.sh";

			lock = "systemctl suspend & hyprlock";
  		};
  		history = {
    			size = 10000;
    			path = "${config.xdg.dataHome}/zsh/history";
  		};
		
		oh-my-zsh = {
			enable = true;
			plugins = [ "git" ];
			theme = "robbyrussell";
		};
	};

	programs.rofi = {
		enable = true;
		package = pkgs.rofi-wayland;
		location = "center";
		theme = "~/.config/rofi/gruvbox-material.rasi";
	};

	programs.git = {
		enable = true;
		userName = "Irgendeinwer";
		userEmail = "irgendeinwer@proton.me";
		extraConfig = {
			init.defaultBranch = "main";
		};

	};

	programs.lf = {
		enable = true;
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
