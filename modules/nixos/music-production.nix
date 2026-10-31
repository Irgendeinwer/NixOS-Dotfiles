{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.audio.production;

  # Link REAPER directly against PipeWire's native libjack so its JACK backend
  # talks straight to PipeWire without loading standalone libjack2.
  reaperWithPipewireJack = pkgs.reaper.override {
    jackLibrary = pkgs.pipewire.jack;
  };

  pluginFormats = [
    "clap"
    "dssi"
    "ladspa"
    "lv2"
    "lxvst"
    "vst"
    "vst3"
  ];
in
{
  options.custom.audio.production = {
    enable = lib.mkEnableOption "real-time audio pipeline, REAPER DAW, and digital synth/breakcore production stack";

    user = lib.mkOption {
      type = lib.types.str;
      default = config.custom.user;
      defaultText = lib.literalExpression "config.custom.user";
      description = "User account granted real-time audio and PipeWire privileges.";
    };

    yabridge = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install yabridge, yabridgectl, and Wine for bridging Windows VST2/VST3/CLAP plugins.";
      };
    };

    sampleRate = lib.mkOption {
      type = lib.types.int;
      default = 48000;
      description = "Default PipeWire sample rate in Hz.";
    };

    quantum = lib.mkOption {
      type = lib.types.int;
      default = 128;
      description = "Target PipeWire JACK buffer quantum in frames while DAW/JACK clients run (~2.7 ms at 48 kHz).";
    };

    minQuantum = lib.mkOption {
      type = lib.types.int;
      default = 64;
      description = "Minimum allowed PipeWire buffer quantum in frames (~1.3 ms at 48 kHz).";
    };

    idleQuantum = lib.mkOption {
      type = lib.types.int;
      default = 1024;
      description = "Relaxed PipeWire buffer quantum in frames when no low-latency JACK client is active (~21.3 ms at 48 kHz).";
    };

    extraPlugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional audio plugin packages to install and expose to REAPER and other plugin hosts.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Keep the desktop PipeWire & routing stack active alongside production
    custom.desktop.sound.enable = lib.mkDefault true;

    # 1. Real-time kernel, IRQ threading, ALSA MIDI & VM tuning
    boot = {
      kernelParams = [
        "preempt=full"
        "threadirqs"
      ];
      kernelModules = [
        "snd-seq"
        "snd-rawmidi"
      ];
      kernel.sysctl = {
        # Keep sample libraries and wavetables resident in RAM
        "vm.swappiness" = lib.mkDefault 10;
        # Support large breakbeat/sample folders in REAPER Media Explorer & yabridge
        "fs.inotify.max_user_watches" = lib.mkDefault 524288;
      };
    };

    # 2. Hardware timer access & dynamic C-state DMA latency lock
    # Allows REAPER/PipeWire to hold /dev/cpu_dma_latency open only while audio
    # is active, preventing deep CPU C-state xruns without locking idle clocks 24/7.
    services.udev.extraRules = ''
      KERNEL=="rtc0", GROUP="audio"
      KERNEL=="hpet", GROUP="audio"
      DEVPATH=="/devices/virtual/misc/cpu_dma_latency", OWNER="root", GROUP="audio", MODE="0660"
    '';

    # 3. Real-time scheduling privileges, memlock & Wine Esync/Fsync fd limits
    security.rtkit.enable = true;
    users.users.${cfg.user}.extraGroups = [
      "audio"
      "pipewire"
    ];

    security.pam.loginLimits = [
      {
        domain = "@audio";
        item = "memlock";
        type = "-";
        value = "unlimited";
      }
      {
        domain = "@audio";
        item = "rtprio";
        type = "-";
        value = "98";
      }
      {
        domain = "@audio";
        item = "nice";
        type = "-";
        value = "-19";
      }
      {
        domain = "@audio";
        item = "nofile";
        type = "soft";
        value = "524288";
      }
      {
        domain = "@audio";
        item = "nofile";
        type = "hard";
        value = "524288";
      }
    ];

    # 4. Dynamic low-latency PipeWire & native JACK emulation
    services.pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
      jack.enable = true;

      extraConfig = {
        # Dynamic quantum: stays relaxed (`idleQuantum`) for desktop audio,
        # Discord, EasyEffects and HeSuVi, and drops automatically when REAPER
        # or another JACK/pro-audio client opens.
        pipewire."15-low-latency" = {
          "context.properties" = {
            "default.clock.rate" = cfg.sampleRate;
            "default.clock.allowed-rates" = [
              44100
              48000
              88200
              96000
            ];
            "default.clock.quantum" = cfg.idleQuantum;
            "default.clock.min-quantum" = cfg.minQuantum;
            "default.clock.max-quantum" = 2048;
          };
        };

        # Native PipeWire JACK client profile: requests `quantum/sampleRate`
        # automatically for REAPER/Carla/Cardinal and exposes MIDI ports.
        jack."10-pro-audio" = {
          "jack.properties" = {
            "node.latency" = "${toString cfg.quantum}/${toString cfg.sampleRate}";
            "jack.merge-monitor" = true;
            "jack.show-midi" = true;
            "jack.short-name" = true;
          };
        };
      };
    };

    # 5. System-wide plugin search paths (exported early via PAM for Wayland/Hyprland)
    environment = {
      pathsToLink = map (format: "/lib/${format}") pluginFormats;

      sessionVariables = {
        CLAP_PATH = [ "$HOME/.clap" ];
        DSSI_PATH = [ "$HOME/.dssi" ];
        LADSPA_PATH = [ "$HOME/.ladspa" ];
        LV2_PATH = [ "$HOME/.lv2" ];
        LXVST_PATH = [ "$HOME/.lxvst" ];
        VST_PATH = [ "$HOME/.vst" ];
        VST3_PATH = [ "$HOME/.vst3" ];
      };

      profileRelativeSessionVariables = {
        CLAP_PATH = [ "/lib/clap" ];
        DSSI_PATH = [ "/lib/dssi" ];
        LADSPA_PATH = [ "/lib/ladspa" ];
        LV2_PATH = [ "/lib/lv2" ];
        LXVST_PATH = [ "/lib/lxvst" ];
        VST_PATH = [ "/lib/vst" ];
        VST3_PATH = [ "/lib/vst3" ];
      };

      # Core DAW, modular rack host, PipeWire patchbay, and optional Windows VST bridge.
      # Keeping yabridge in systemPackages ensures NIX_PROFILES exposes libyabridge-*.so
      # to the nixpkgs-patched chainloader at runtime.
      systemPackages = [
        reaperWithPipewireJack
        pkgs.carla
        pkgs.crosspipe
      ]
      ++ lib.optionals cfg.yabridge.enable [
        pkgs.yabridge
        pkgs.yabridgectl
        pkgs.wineWow64Packages.yabridge
        pkgs.winetricks
      ];
    };
  };
}
