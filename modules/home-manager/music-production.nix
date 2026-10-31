{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  cfg = config.custom.audio.production;

  osProductionEnabled = osConfig != null && (osConfig.custom.audio.production.enable or false);

  extraPlugins =
    if osConfig != null then (osConfig.custom.audio.production.extraPlugins or [ ]) else [ ];

  arch = pkgs.stdenv.hostPlatform.parsed.cpu.name;

  # Work around NixOS/nixpkgs#577387 & #579810: patchelf 0.19.2 corrupts prebuilt
  # ELF binaries (REAPER, Vital) during autoPatchelfHook, causing ld-linux to
  # segfault on startup.
  patchelf015 = pkgs.patchelf.overrideAttrs (
    finalAttrs: _: {
      version = "0.15.2";
      src = pkgs.fetchurl {
        url = "https://github.com/NixOS/patchelf/releases/download/${finalAttrs.version}/patchelf-${finalAttrs.version}.tar.bz2";
        hash = "sha256-F3RfVkFZyOIo/EEtplogSLhGxLa0Igt3y/IkFuAvLXw=";
      };
    }
  );

  withPatchelf015 =
    pkg:
    pkg.overrideAttrs (old: {
      nativeBuildInputs = [ patchelf015 ] ++ (old.nativeBuildInputs or [ ]);
      preFixup = ''
        export PATH="${patchelf015}/bin:$PATH"
      ''
      + (old.preFixup or "");
    });

  # Curated digital breakcore, jungle, glitch & synth production suite.
  # Stock nixpkgs packages are kept unmodified to preserve cache.nixos.org hits
  # (except prebuilt binaries affected by patchelf 0.19.2).
  builtinPlugins = with pkgs; [
    # --- Ported Linux Synth & FX Collection (Obxd, TAL-NoiseMaker/Dub/Vocoder, Temper, Luftikus) ---
    distrho-ports

    # --- Flagship Digital, Wavetable, FM, Chiptune & Modular Synthesizers ---
    (withPatchelf015 vital) # Spectral warping wavetable synth (Reese basses, neuro growls, digital leads)
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
    bespokesynth # Node-based modular live-coding, glitch & resampling playground

    # --- Breakbeat Slicing, Drum Synthesis, Samplers & Glitch Sequencers ---
    ninjas2 # Transient-based beat slicer built for chopping Amen/drum breaks to MIDI
    chow-kick # Nonlinear physical-modeling kick synth (jungle subs to distorted gabber kicks)
    geonkick # Multi-layer percussive & industrial/hardcore kick/snare synthesizer
    sfizz-ui # SFZ multisample instrument & sliced break kit player (with GUI)
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

  # Flat VST2 directory of leaf symlinks so recursive scanners traverse ~/.vst/nix
  # as a real directory alongside ~/.vst/yabridge.
  vst2PluginDirectory = pkgs.runCommandLocal "reaper-vst-plugins" { } ''
    mkdir -p "$out"
    for pkg in ${lib.escapeShellArgs (map toString allPlugins)}; do
      src="$pkg/lib/vst"
      if [ -d "$src" ]; then
        cp -rsf --no-preserve=mode "$src"/. "$out/"
      fi
    done
  '';

  # Materialize real `<Bundle>.vst3/Contents/<arch>-linux/` directories so C++
  # `recursive_directory_iterator` and REAPER's `WDL_DirScan` traverse every
  # bundle, while keeping `Contents/Resources` as a single directory symlink
  # (paired with `ignorelinks = true`) to avoid expanding thousands of asset
  # files (e.g. Cardinal's VCV module SVGs) during Home Manager activation.
  vst3PluginDirectory = pkgs.runCommandLocal "reaper-vst3-plugins" { } ''
    mkdir -p "$out"
    for pkg in ${lib.escapeShellArgs (map toString allPlugins)}; do
      src="$pkg/lib/vst3"
      [ -d "$src" ] || continue
      for bundle in "$src"/*; do
        [ -e "$bundle" ] || continue
        bname="$(basename "$bundle")"
        if [ -d "$bundle/Contents" ]; then
          mkdir -p "$out/$bname/Contents"
          for entry in "$bundle"/*; do
            [ -e "$entry" ] || continue
            ename="$(basename "$entry")"
            [ "$ename" = "Contents" ] && continue
            ln -sfn "$entry" "$out/$bname/$ename"
          done
          for centry in "$bundle/Contents"/*; do
            [ -e "$centry" ] || continue
            cname="$(basename "$centry")"
            if [ -d "$centry" ] && [ "$cname" != "Resources" ]; then
              mkdir -p "$out/$bname/Contents/$cname"
              for bin in "$centry"/*; do
                [ -e "$bin" ] || continue
                ln -sfn "$bin" "$out/$bname/Contents/$cname/$(basename "$bin")"
              done
            else
              ln -sfn "$centry" "$out/$bname/Contents/$cname"
            fi
          done
        else
          ln -sfn "$bundle" "$out/$bname"
        fi
      done
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
    "${config.home.profileDirectory}/lib/${format}"
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

    yabridge.enable = lib.mkOption {
      type = lib.types.bool;
      default =
        if osConfig != null then (osConfig.custom.audio.production.yabridge.enable or true) else true;
      defaultText = lib.literalExpression "osConfig.custom.audio.production.yabridge.enable or true";
      description = "Enable the yabridge-sync helper and Windows VST bridging integration.";
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages =
        allPlugins
        ++ lib.optional cfg.yabridge.enable yabridgeSync
        ++ lib.optionals (!osProductionEnabled) (
          [
            (withPatchelf015 (pkgs.reaper.override { jackLibrary = pkgs.pipewire.jack; }))
            pkgs.carla
            pkgs.crosspipe
          ]
          ++ lib.optionals cfg.yabridge.enable [
            pkgs.yabridge
            pkgs.yabridgectl
            pkgs.wineWow64Packages.yabridge
            pkgs.winetricks
          ]
        );

      # Collapse any pre-existing expanded Contents/Resources trees from older
      # generations before Home Manager replaces them with single symlinks.
      activation.cleanupLegacyVst3Resources = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        if [[ ! -v DRY_RUN && -d "$HOME/.vst3/nix" ]]; then
          for res in "$HOME"/.vst3/nix/*.vst3/Contents/Resources; do
            if [[ -d "$res" && ! -L "$res" ]]; then
              ${pkgs.findutils}/bin/find "$res" -type l -lname "${builtins.storeDir}/*" -delete
              ${pkgs.findutils}/bin/find "$res" -depth -type d -exec ${pkgs.coreutils}/bin/rmdir --ignore-fail-on-non-empty {} +
            fi
          done
        fi
      '';

      # REAPER's default Linux VST path scans ~/.vst and ~/.vst3 (Steinberg's
      # VST3 spec has no standard VST3_PATH env var). Linking into a dedicated
      # `nix/` subdirectory keeps declarative plugins isolated from `yabridge/`
      # while CLAP and LV2 are discovered once via CLAP_PATH / LV2_PATH.
      file = {
        ".vst/nix" = {
          source = vst2PluginDirectory;
          recursive = true;
        };
        ".vst3/nix" = {
          source = vst3PluginDirectory;
          recursive = true;
          ignorelinks = true;
        };
      };

      # When the NixOS module is active, PAM exports plugin paths system-wide;
      # populate sessionSearchVariables only when HM runs without the NixOS layer.
      sessionSearchVariables = lib.mkIf (!osProductionEnabled) {
        CLAP_PATH = standaloneSearchPaths "clap";
        DSSI_PATH = standaloneSearchPaths "dssi";
        LADSPA_PATH = standaloneSearchPaths "ladspa";
        LV2_PATH = standaloneSearchPaths "lv2";
        LXVST_PATH = standaloneSearchPaths "lxvst";
        VST_PATH = [ "${config.home.homeDirectory}/.vst" ];
        VST3_PATH = [ "${config.home.homeDirectory}/.vst3" ];
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
