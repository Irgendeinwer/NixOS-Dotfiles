{ pkgs, ... }:
{
  programs.mpv = {
    enable = true;

    scripts = with pkgs.mpvScripts; [
      uosc             # The best Proximity-UI (essential for minimalism)
      mpris            # Allows Hyprland/Waybar to control the player
      thumbfast        # High-speed seekbar previews (integrated with uosc)
      sponsorblock     # Automatically skips sponsorships in YouTube links
      quality-menu     # uosc-style menu for selecting stream resolutions
    ];

    config = {
      # --- Playback Behavior ---
      loop-file = "inf";    	    # "inf" means infinite loop for the current file
      shuffle = "yes";		    # Randomize the playlist on startup

      # --- Rendering ---
      vo = "gpu-next";              # Use the modern libplacebo-based renderer
      gpu-context = "wayland";      # Wayland-native (crucial for Hyprland)
      hwdec = "auto-safe";          # Hardware decoding for 4K efficiency
      profile = "high-quality";     # Enables better scaling and debanding

      # --- Wayland / Hyprland Color Fixes ---
      target-colorspace-hint = "no"; 

      # --- Audio Quality ---
      ao = "pipewire";
      audio-channels = "stereo";    # Optimized for headphones
      gapless-audio = "yes";        # Essential for your Music/Audiobooks
      volume-max = 100;             # Keep at 100%

      # --- Visuals & UI ---
      osc = "no";                   # Disable default UI (uosc takes over)
      osd-bar = "no";               # Hide default progress bar
      border = "no";                # Cleaner look for tiling WMs
      cursor-autohide = 500;        # Hide cursor faster

      # --- Behavior ---
      keep-open = "yes";            # Don't close window when media ends
      save-position-on-quit = "yes";# Perfect for long Audiobooks
      pause = "no";                 # Auto-play on start
    };

    # Custom keybinds for the uosc interface
    bindings = {
      "tab" = "script-binding uosc/menu";
      "s" = "script-binding uosc/subtitles";
      "a" = "script-binding uosc/audio";
      "q" = "script-binding uosc/quality";
      "p" = "script-binding uosc/items";      # Show playlist
      "right" = "seek 5";
      "left" = "seek -5";
    };
  };
}
