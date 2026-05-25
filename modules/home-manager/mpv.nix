{ pkgs, ... }:
{
  programs.mpv = {
    enable = true;

    scripts = with pkgs.mpvScripts; [
      uosc
      mpris
      thumbfast
      sponsorblock
      quality-menu
    ];

    profiles = {
      multichannel = {
        profile-cond = "p[\"audio-params/channel-count\"] > 2";
        audio-device = "pipewire/effect_input.virtual-surround-7.1-hesuvi";
      };
    };

    config = {
      # Playback & Hardware
      vo = "gpu-next";
      gpu-api = "vulkan";
      gpu-context = "waylandvk";
      hwdec = "auto-safe";
      profile = "high-quality";
      target-colorspace-hint = "yes";

      loop-file = "inf";
      shuffle = "yes";
      keep-open = "yes";
      save-position-on-quit = "yes";
      pause = "no";

      # Audio
      ao = "pipewire";
      audio-channels = "auto-safe";
      gapless-audio = "yes";
      volume-max = 100;

      # UI (Delegated to uosc)
      osc = "no";
      osd-bar = "no";
      border = "no";
      cursor-autohide = 500;

      # YouTube / Streaming
      ytdl-format = "bestvideo+bestaudio/best";

      # Caching
      cache = "yes";
      demuxer-max-bytes = "400M";
      demuxer-max-back-bytes = "150M";

      # Subtitles & Languages
      slang = "eng,en";
      alang = "eng,en";
      sub-auto = "fuzzy";
    };

    bindings = {
      # uosc menus
      "tab" = "script-binding uosc/menu";
      "MBTN_RIGHT" = "script-binding uosc/menu";
      "c" = "script-binding uosc/chapters";
      "p" = "script-binding uosc/playlist";
      "s" = "script-binding uosc/subtitles";
      "a" = "script-binding uosc/audio";
      "Q" = "script-binding uosc/stream-quality";

      # Window & Playback Controls
      "q" = "quit";
      "SPACE" = "cycle pause";
      "MBTN_LEFT" = "cycle pause";
      "f" = "cycle fullscreen";
      "MBTN_LEFT_DBL" = "cycle fullscreen";

      # Seeking
      "right" = "seek 5";
      "left" = "seek -5";
      "shift+right" = "seek 1 exact";
      "shift+left" = "seek -1 exact";

      # Volume
      "WHEEL_UP" = "add volume 5";
      "up" = "add volume 5";
      "WHEEL_DOWN" = "add volume -5";
      "down" = "add volume -5";

      # Speed Control
      "[" = "add speed -0.1";
      "]" = "add speed 0.1";
      "BS" = "set speed 1.0";

      # Video adjustments
      "r" = "cycle_values video-rotate 90 180 270 0";

      # Information & Utilities
      "i" = "show-text \"\${path}\" 3000";
      "I" = "script-binding stats/display-stats";
      "ctrl+i" = "script-binding stats/display-stats-toggle";
    };
  };
}
