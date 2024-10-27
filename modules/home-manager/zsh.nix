{ config, pkgs, ... }:
{
	programs.zsh = {
  		enable = true;
  		enableCompletion = true;
  		autosuggestion.enable = true;
  		syntaxHighlighting.enable = true;

		shellAliases = {
			config = "cd ~/dotfiles/ && nvim hosts/junixos/configuration.nix";
			hconfig = "cd ~/dotfiles/ && nvim hosts/junixos/hardware-configuration.nix";
			flake = "cd ~/dotfiles/ && nvim flake.nix";
			home = "cd ~/dotfiles/ && nvim hosts/junixos/home.nix";
			hypr = "cd ~/dotfiles/ && nvim modules/home-manager/hypr/";

    			rb = "~/dotfiles/modules/scripts/rebuild.sh";
			rebuild = "sudo nixos-rebuild switch --flake ~/dotfile/#$HOST";

			stfu = "git -C ~/dotfiles/ push && systemctl poweroff";
			lock = "systemctl suspend & hyprlock";
  		};
  		history = {
    			size = 10000;
    			path = "${config.xdg.dataHome}/zsh/history";
  		};
		
		oh-my-zsh = {
			enable = true;
			plugins = [ "git" "direnv" ];
			theme = "robbyrussell";
		};
	};

}
