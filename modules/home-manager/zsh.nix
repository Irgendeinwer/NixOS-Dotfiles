{ config, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
    	config = "cd ~/dotfiles/ && nvim hosts/$HOST/configuration.nix";
	hconfig = "cd ~/dotfiles/ && nvim hosts/$HOST/hardware-configuration.nix";
	flake = "cd ~/dotfiles/ && nvim flake.nix";
	home = "cd ~/dotfiles/ && nvim hosts/$HOST/home.nix";
	hypr = "cd ~/dotfiles/ && nvim modules/home-manager/hypr/";

	rb = "~/dotfiles/modules/scripts/rebuild.sh";
	rebuild = "sudo nixos-rebuild switch --flake ~/dotfiles/#$HOST";

	stfu = "git -C ~/dotfiles/ push && systemctl poweroff";
	lock = "systemctl suspend & hyprlock";

	# yt-dlp aliases
	dl-music = "yt-dlp -f bestaudio -x --audio-format opus --add-metadata --parse-metadata \"playlist_index:%(track_number)s\" --embed-thumbnail -o \"%(title)s.%(ext)s\"";
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
