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

      # yt-dlp aliases
      dl-music = ''yt-dlp -f bestaudio -x --audio-format opus --add-metadata --parse-metadata "playlist_index:%(track_number)s" --embed-thumbnail -o "%(title)s.%(ext)s"'';
    };

    # Renamed from initExtra to initContent based on your error
    initContent = ''
            listen() {
              local matches
              matches=$(nix run nixpkgs#fd -- -e opus -e flac -e mp3 -e wav -e m4a -a . ~/music \
                        | nix run nixpkgs#fzf -- --filter "$*")

              if [ -z "$matches" ]; then
                echo "No music found matching: $*"
                return 1
              fi

              # 1. display-tags="": Hides the ugly monochrome "File tags" block
              # 2. term-playing-msg: Rebuilds the stats manually with colors
              #    - Line 1: Title (Bold Green)
              #    - Line 2: Artist (Bold Cyan) on Album (Grey)
              #    - Line 3: Date (Yellow) • Genre (Magenta)
              echo "$matches" | nix run nixpkgs#mpv -- \
      	    --no-shuffle \
      	    --loop=no \
      	    --no-resume-playback \
                  --no-video \
                  --term-osd-bar \
                  --msg-color \
                  --msg-level=playlist=error,file=error \
                  --display-tags="" \
                  --term-playing-msg=$'\n\e[1;32m''${media-title}\e[0m\n\e[1;36m''${metadata/artist} \e[0;90mon \e[0;37m''${metadata/album}\e[0m\n\e[0;33m''${metadata/date} \e[0;90m• \e[0;35m''${metadata/genre}\e[0m' \
                  --playlist=-
            }
    '';

    history = {
      size = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "direnv"
      ];
      theme = "robbyrussell";
    };
  };
}
