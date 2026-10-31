{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  cfg = config.custom.audio.production;

  yabridgeEnabled =
    if osConfig != null then (osConfig.custom.audio.production.yabridge.enable or true) else true;

  extraPlugins =
    if osConfig != null then (osConfig.custom.audio.production.extraPlugins or [ ]) else [ ];

  arch = pkgs.stdenv.hostPlatform.parsed.cpu.name;

  # Curated digital breakcore, jungle, glitch & synth production suite.
  # Note: distrho-ports goes first so newer standalone builds (e.g. dexed,
  # vital) take precedence when populating shared VST directories.
  builtinPlugins = with pkgs; [
    # --- Ported Linux Synth & FX Collection (Obxd, TAL-NoiseMaker/Dub/Vocoder, Temper, Luftikus) ---
    distrho-ports

    # --- Flagship Digital, Wavetable, FM, Chiptune & Modular Synthesizers ---
    vital # Spectral warping wavetable synth (Reese basses, neuro growls, digital leads)
    surge-xt # Hybrid wavetable / FM / Plaits synth + Surge XT Effects rack
    odin2 # 24-voice semi-modular wavetable, chiptune & analog/formant synth
    vaporizer2 # Additive / wavetable resynthesis & sampler workstation
    helm # Polyphonic digital synth with stutter, formant filter & visual modulation
    six-sines # 6-operator TX81Z/DX-style audio-rate FM/PM synth
    dexed # Yamaha DX7 6-operator FM synth (classic 90s jungle/rave basses & FM percussion)
    adlplug # OPL3 (YM3812) hardware FM chip synth for tracker/chiptune grit
    opnplug # OPN2 (YM2612 Sega Genesis) 4-operator FM chip synth
    zynaddsubfx # Additive + subtractive + PADsynth engine for lush atmospheric pads
    cardinal # Self-contained VCV Rack modular synth & FX studio (1000+ modules)
    plugdata # Visual Pure Data DSP & algorithmic glitch patching environment
    bespokesynth # Node-based modular live-coding, glitch & resampling playground

    # --- Breakbeat Slicing, Drum Synthesis, Samplers & Glitch Sequencers ---
    ninjas2 # Transient-based beat slicer built for chopping Amen/drum breaks to MIDI
    chow-kick # Nonlinear physical-modeling kick synth (jungle subs to distorted gabber kicks)
    geonkick # Multi-layer percussive & industrial/hardcore kick/snare synthesizer
    sfizz-ui # SFZ multisample instrument & sliced break kit player (with GUI)
    decent-sampler # Sample player for DecentSampler (.dspreset / .dslibrary) libraries
    samplv1 # Polyphonic pitch-shifting / looping sampler synth
    drumkv1 # Drum-kit one-shot sampler plugin
    bchoppr # Rhythmic audio stream chopper & step gate
    bslizr # Sequenced step beat slicer & repeater
    bjumblr # Pattern-controlled live audio stream / breakbeat rearranger
    boops # Multi-FX glitch step sequencer (stutter, tape-stop, crush, ringmod, pitch)
    stochas # Polyrhythmic & probabilistic MIDI step sequencer for drill/snare rolls

    # --- Distortion, Waveshaping, Console/Tape Crunch, Mixing & Space ---
    fire # Multiband waveshaping distortion (Rift/Trash-style Reese & break mangling)
    wolf-shaper # Spline-based asymmetric/foldback waveshaper with oscilloscope
    chow-tape-model # Analog tape saturation, chew, flutter & lo-fi degradation
    chow-phaser # Nonlinear feedback phaser for Reese bass movement
    airwin2rack # 300+ Airwindows processors in one GUI rack (Mackity CR1604 clip, BitGlitter, DeRez, Galactic)
    lsp-plugins # Studio mixing/mastering suite (Spectrum EQ, OTT-style Multiband Comp, Clipper, Limiter, Transient)
    calf # Studio FX (Crusher bitcrusher/sample-rate reducer, Vintage Delay, Saturator, Exciter)
    zam-plugins # Mastering dynamics, saturators & EQs
    x42-plugins # Pro EBU R128 loudness, phase/mono correlation & spectrum meters + MIDI utilities
    dragonfly-reverb # Lush algorithmic Hall, Plate, Room & Early Reflections reverbs
  ];

  allPlugins = builtinPlugins ++ extraPlugins;

  # Materialize real directories containing leaf symlinks so every recursive
  # VST scanner (REAPER WDL_DirScan, JUCE/C++ recursive_directory_iterator)
  # traverses bundles reliably without colliding with ~/.vst*/yabridge/.
  pluginDirectory =
    format:
    pkgs.runCommandLocal "reaper-${format}-plugins" { } ''
      mkdir -p "$out"
      for pkg in ${lib.escapeShellArgs (map toString allPlugins)}; do
        src="$pkg/lib/${format}"
        if [ -d "$src" ]; then
          cp -rsf --no-preserve=mode "$src"/. "$out/"
        fi
      done
    '';

  yabridgeSync = pkgs.writeShellApplication {
    name = "yabridge-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.wineWow64Packages.yabridge
      pkgs.yabridgectl
    ];
    text = builtins.readFile ./scripts/yabridge-sync.sh;
  };

  standaloneSearchPaths = format: [
    "${config.home.homeDirectory}/.${format}"
    "${config.home.homeDirectory}/.nix-profile/lib/${format}"
    "/etc/profiles/per-user/${config.home.username}/lib/${format}"
    "/run/current-system/sw/lib/${format}"
  ];
in
{
  options.custom.audio.production = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = if osConfig != null then (osConfig.custom.audio.production.enable or false) else true;
      defaultText = lib.literalExpression "osConfig.custom.audio.production.enable or true";
      description = "Declarative REAPER extensions, breakcore/synth plugins, and per-user VST linking.";
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages =
        allPlugins
        ++ lib.optional yabridgeEnabled yabridgeSync
        ++ lib.optionals (osConfig == null) (
          [
            (pkgs.reaper.override { jackLibrary = pkgs.pipewire.jack; })
            pkgs.carla
            pkgs.crosspipe
          ]
          ++ lib.optionals yabridgeEnabled [
            pkgs.yabridge
            pkgs.yabridgectl
            pkgs.wineWow64Packages.yabridge
            pkgs.winetricks
          ]
        );

      # REAPER's default Linux VST path scans ~/.vst and ~/.vst3 (Steinberg's
      # VST3 spec has no standard VST3_PATH env var). Linking into a dedicated
      # `nix/` subdirectory keeps declarative plugins isolated from `yabridge/`
      # while CLAP and LV2 are discovered once via CLAP_PATH / LV2_PATH.
      file = {
        ".vst/nix" = {
          source = pluginDirectory "vst";
          recursive = true;
        };
        ".vst3/nix" = {
          source = pluginDirectory "vst3";
          recursive = true;
        };
      };

      # On NixOS, PAM exports plugin paths system-wide (modules/nixos/music-production.nix);
      # populate sessionSearchVariables only for standalone Home Manager evaluations.
      sessionSearchVariables = lib.mkIf (osConfig == null) {
        CLAP_PATH = standaloneSearchPaths "clap";
        DSSI_PATH = standaloneSearchPaths "dssi";
        LADSPA_PATH = standaloneSearchPaths "ladspa";
        LV2_PATH = standaloneSearchPaths "lv2";
        LXVST_PATH = standaloneSearchPaths "lxvst";
        VST_PATH = standaloneSearchPaths "vst";
        VST3_PATH = standaloneSearchPaths "vst3";
      };
    };

    # Declaratively wire SWS (with MPC/breakbeat Groove Tool templates) and
    # ReaPack into ~/.config/REAPER while keeping ~/.config/REAPER mutable for
    # REAPER preferences, ReaPack downloads, JSFX, and user templates.
    xdg.configFile = {
      "REAPER/UserPlugins/reaper_sws-${arch}.so".source =
        "${pkgs.reaper-sws-extension}/UserPlugins/reaper_sws-${arch}.so";
      "REAPER/Scripts/sws_python.py".source = "${pkgs.reaper-sws-extension}/Scripts/sws_python.py";
      "REAPER/Scripts/sws_python64.py".source = "${pkgs.reaper-sws-extension}/Scripts/sws_python64.py";
      "REAPER/Data/Grooves" = {
        source = "${pkgs.reaper-sws-extension}/Data/Grooves";
        recursive = true;
      };
      "REAPER/UserPlugins/reaper_reapack-${arch}.so".source =
        "${pkgs.reaper-reapack-extension}/UserPlugins/reaper_reapack-${arch}.so";
    };
  };
}
