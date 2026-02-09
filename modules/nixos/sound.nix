{
  lib,
  config,
  pkgs,
  ...
}:
{
  options = {
    sound-module = {
      enable = lib.mkEnableOption "sound-module";
    };
  };
  config = lib.mkIf config.sound-module.enable {
    environment.systemPackages = with pkgs; [
      alsa-utils
      qpwgraph       # Essential for visual routing
      pulseaudioFull
      pulsemixer
      pavucontrol
      pamixer
    ];
    security.rtkit.enable = true;
    
    services.pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
      
      # Define Virtual Sinks and Sources
      extraConfig.pipewire = {
        # 1. THE MIC SOURCE (For Chromium/Discord)
        # This creates a loopback: audio sent to 'obs_mic_sink' 
        # comes out of 'obs_mic_source' which Chromium sees as a Mic.
        "10-obs-virtual-mic" = {
          "context.modules" = [
            {
              name = "libpipewire-module-loopback";
              args = {
                "node.description" = "OBS Virtual Microphone";
                "capture.props" = {
                  "node.name" = "obs_mic_sink";
                  "media.class" = "Audio/Sink";
                  "audio.position" = [ "FL" "FR" ];
                };
                "playback.props" = {
                  "node.name" = "obs_mic_source";
                  "media.class" = "Audio/Source";
                  "audio.position" = [ "FL" "FR" ];
                };
              };
            }
          ];
        };

        # 2. YOUR ORIGINAL DEVICES
        "99-virtual-devices" = {
          "context.objects" = [
            # The Raw Input (From Android)
            {
              factory = "adapter";
              args = {
                "factory.name" = "support.null-audio-sink";
                "node.name" = "AndroidMic-Sink";
                "node.description" = "Raw Android Input";
                "media.class" = "Audio/Sink";
                "audio.position" = "FL,FR";
              };
            }
            # The Processed Output (To Discord)
            {
              factory = "adapter";
              args = {
                "factory.name" = "support.null-audio-sink";
                "node.name" = "VoiceChanger-Output";
                "node.description" = "AI Voice Output";
                "media.class" = "Audio/Sink";
                "audio.position" = "FL,FR";
              };
            }
          ];
        };
      };
    };
  };
}
