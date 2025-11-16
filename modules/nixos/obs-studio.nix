{ pkgs, ... }:
{
  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;

    plugins = with pkgs.obs-studio-plugins; [
      # --- Minimal Essentials (Performance & System Integration) ---
      wlrobs-unstable             # Screen capture for Hyprland
      obs-pipewire-audio-capture  # Audio capture with PipeWire
      obs-vkcapture               # High-performance game capture
      obs-vaapi                   # Hardware encoding (AMD/Intel)
      obs-gstreamer               # Dependency for VA-API

      # --- High-Impact Workflow & Visuals (Your List) ---
      obs-websocket               # Remote control (Stream Deck, etc.)
      obs-move-transition         # Professional animated scene transitions
      advanced-scene-switcher     # Automate your scene switching
      obs-source-record           # Record clean, individual sources for editing
      obs-backgroundremoval       # AI background removal without a green screen
      obs-input-overlay           # Display keyboard/mouse/gamepad inputs
    ];
  };
}
