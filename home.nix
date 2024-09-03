{ config, pkgs, ... }:
{
	home.username = "julian";
	home.homeDirectory = "/home/julian";

	imports = [
		./modules/home-manager/hyprland.nix
		./modules/home-manager/hyprlock.nix
	];

	home.packages = with pkgs; [
		signal-desktop
	];

	# wayland.windowManager.hyprland = {
	#	enable = true;
	#	plugins = [];
	#	systemd.variables = ["--all"];
	#	#settings = {
	#	#	bind = []
	#	#};
	#	extraConfig = ''
	#		$terminal = kitty
	#	'';
	# };

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
    			rebuild = "~/dotfiles/scripts/rebuild.sh";
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
