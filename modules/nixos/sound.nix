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
      qpwgraph
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
      extraConfig.pipewire."99-virtual-mic" = {
        "context.objects" = [
        {
          factory = "adapter";
          args = {
            "factory.name" = "support.null-audio-sink";
            "node.name" = "AndroidMic-Sink";
            "node.description" = "AndroidMic Virtual Device";
            "media.class" = "Audio/Sink";
            "audio.position" = "FL,FR";
          };
        }];
	};
    };
  };
}
