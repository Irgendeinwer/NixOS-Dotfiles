{
  lib,
  config,
  pkgs,
  ...
}:
{
  options.custom.desktop.sound = {
    enable = lib.mkEnableOption "desktop sound configuration (PipeWire, virtual routing)";
  };

  config = lib.mkIf config.custom.desktop.sound.enable {
    environment.systemPackages = with pkgs; [
      alsa-utils
      qpwgraph
      pulseaudioFull
      pulsemixer
      pavucontrol
      pamixer
    ];
    security.rtkit.enable = true;

    networking.firewall = {
      allowedTCPPorts = [ 54345 ]; # AndroidMic
      allowedUDPPorts = [ 54345 ];
    };

    services.pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;

      extraConfig.pipewire = {
        # 1. VIRTUAL MICROPHONE (For Discord / Chromium / AndroidMic destination)
        "10-virtual-mic" = {
          "context.modules" = [
            {
              name = "libpipewire-module-loopback";
              args = {
                "node.description" = "Virtual Microphone";
                "capture.props" = {
                  "node.name" = "mic_sink";
                  "media.class" = "Audio/Sink";
                  "audio.position" = [
                    "FL"
                    "FR"
                  ];
                };
                "playback.props" = {
                  "node.name" = "mic_source";
                  "media.class" = "Audio/Source";
                  "audio.position" = [
                    "FL"
                    "FR"
                  ];
                };
              };
            }
          ];
        };

        # 2. 3-CHANNEL RECORDING DEVICE & AUTOMATIC ROUTING
        "20-multichannel-rec" = {
          "context.objects" = [
            # The 3-channel null sink (Desktop = 1 & 2 [FL, FR], Mic = 3 [FC])
            {
              factory = "adapter";
              args = {
                "factory.name" = "support.null-audio-sink";
                "node.name" = "Combined-Capture-Sink";
                "node.description" = "Desktop & Mic Capture";
                "media.class" = "Audio/Sink";
                "audio.position" = [
                  "FL"
                  "FR"
                  "FC"
                ];
                # Priority 0 ensures WirePlumber never auto-selects this as the default output
                "priority.driver" = 0;
                "priority.session" = 0;
              };
            }
          ];

          "context.modules" = [
            # Route Desktop Audio -> Channels 1 & 2 (FL, FR)
            {
              name = "libpipewire-module-loopback";
              args = {
                "node.description" = "Desktop to Combined Capture";
                "capture.props" = {
                  "node.name" = "capture.desktop_to_combined";
                  "stream.capture.sink" = true;
                  "audio.position" = [
                    "FL"
                    "FR"
                  ];
                  "node.passive" = true;
                  "node.dont-fallback" = true;
                };
                "playback.props" = {
                  "node.name" = "playback.desktop_to_combined";
                  "target.object" = "Combined-Capture-Sink";
                  "audio.position" = [
                    "FL"
                    "FR"
                  ];
                  "stream.dont-remix" = true;
                };
              };
            }

            # Route Microphone Audio -> Channel 3 (FC / Center)
            {
              name = "libpipewire-module-loopback";
              args = {
                "node.description" = "Mic to Combined Capture";
                "capture.props" = {
                  "node.name" = "capture.mic_to_combined";
                  "target.object" = "mic_source";
                  "audio.position" = [
                    "MONO"
                  ];
                  "node.passive" = true;
                  "node.dont-fallback" = true;
                };
                "playback.props" = {
                  "node.name" = "playback.mic_to_combined";
                  "target.object" = "Combined-Capture-Sink";
                  "audio.position" = [
                    "FC"
                  ];
                  "stream.dont-remix" = true;
                };
              };
            }
          ];
        };
      };
    };
  };
}
