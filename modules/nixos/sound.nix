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
      
      # Define Virtual Sinks
      extraConfig.pipewire."99-virtual-devices" = {
        "context.objects" = [
          # 1. The Raw Input (From Android)
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
          # 2. The Processed Output (To Discord)
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
}
