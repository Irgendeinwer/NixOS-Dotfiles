{
  nixpkgs,
  pkgs,
  self,
  sopsModule,
}:
let
  inherit (nixpkgs) lib;
  inherit (lib) mkEnableOption mkOption types;
  scanPaths = import ../lib/scan-paths.nix { inherit lib; };
  systemModules = scanPaths ../modules/nixos;
  userModules = scanPaths ../modules/home-manager;

  # Evaluate the relevant real modules with small option stubs instead of
  # constructing several complete NixOS hosts in a single evaluator.
  system =
    selected:
    (lib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        ../modules/nixos/desktop.nix
        ../modules/nixos/hypr.nix
        ../modules/nixos/fonts.nix
        ../modules/nixos/amdgpu.nix
        ../modules/nixos/isolated-gaming.nix
        ../modules/nixos/power.nix
        ../modules/services/ai.nix
        {
          config._module.check = false;
          options = {
            custom.user = mkOption {
              type = types.str;
              default = "test";
            };
            warnings = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            custom.desktop.greetd.command = mkOption {
              type = types.str;
              default = "another-session";
            };
            custom.desktop.gaming.enable = mkEnableOption "native gaming";
            hardware.amdgpu.opencl.enable = mkEnableOption "OpenCL";
            services.lact.enable = mkEnableOption "LACT";
            services.flatpak.enable = mkEnableOption "Flatpak";
          };
        }
        selected
      ];
    }).config;

  home =
    osConfig: selected:
    (lib.evalModules {
      specialArgs = { inherit osConfig pkgs; };
      modules = [
        ../modules/home-manager/theme.nix
        ../modules/home-manager/gtk.nix
        ../modules/home-manager/qt.nix
        ../modules/home-manager/kitty.nix
        ../modules/home-manager/rofi/rofi.nix
        ../modules/home-manager/mako.nix
        ../modules/home-manager/notify-failure.nix
        ../modules/home-manager/hypr/hyprcursor.nix
        ../modules/home-manager/hypr/wallpaper.nix
        {
          config._module.check = false;
          options = {
            assertions = mkOption {
              type = types.listOf types.attrs;
              default = [ ];
            };
            gtk = {
              enable = mkEnableOption "GTK";
              iconTheme = mkOption {
                type = types.nullOr types.attrs;
                default = null;
              };
              gtk3.extraConfig = mkOption {
                type = types.attrsOf types.anything;
                default = { };
              };
            };
            qt.enable = mkEnableOption "Qt";
            programs.kitty.enable = mkEnableOption "Kitty";
            programs.rofi.enable = mkEnableOption "rofi";
            services.mako.enable = mkEnableOption "mako";
            home = {
              homeDirectory = mkOption {
                type = types.str;
                default = "/home/test";
              };
              pointerCursor.enable = mkEnableOption "cursor theme";
              pointerCursor.hyprcursor.enable = mkEnableOption "Hyprcursor";
            };
            systemd.user.services = mkOption {
              type = types.attrsOf types.anything;
              default = { };
            };
          };
        }
        selected
      ];
    }).config;

  headless = system { };
  hypr = system { custom.desktop.hyprland.enable = true; };
  x11 = system { custom.desktop.enable = true; };
  wayland = system { custom.desktop.wayland.enable = true; };
  desktopOptOut = system {
    custom.desktop.hyprland.enable = true;
    custom.desktop.enable = false;
  };
  # These names are nested for organization, not parent dependencies.
  independent = system {
    custom.desktop.gaming.isolated.enable = true;
    custom.hardware.amdgpu.lact.enable = true;
  };
  x11Home = home x11 { };
  waylandHome = home wayland {
    custom.theme.wallpaper = {
      path = "/tmp/test-wallpaper.mp4";
      backend = "mpvpaper";
    };
  };
  hyprHome = home hypr { };
  optOutHome = home desktopOptOut { };
  standaloneHome = home null { };

  # Exercise the real NixOS base and portal modules, not just the desktop
  # toggle declarations. i3 does not automatically provide a portal backend.
  x11System =
    (nixpkgs.lib.nixosSystem {
      modules = [
        sopsModule
        ../modules/nixos/base.nix
        ../modules/nixos/desktop.nix
        ../modules/nixos/hypr.nix
        ../modules/nixos/greetd.nix
        {
          networking.hostName = "x11-test";
          nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system;
          system.stateVersion = "26.11";
          custom.desktop.enable = true;
          services.xserver = {
            enable = true;
            windowManager.i3.enable = true;
          };
        }
      ];
    }).config;

  monitorConfig =
    monitors:
    (system { custom.desktop.hyprland.monitors = monitors; }).custom.desktop.hyprland.monitors;
  isValid = value: (builtins.tryEval (builtins.deepSeq value true)).success;
  validMonitors = monitorConfig [
    {
      output = "DP-1";
      extraMetadata = "allowed";
    }
  ];
  invalidScale = monitorConfig [
    {
      output = "DP-1";
      scale = 0;
    }
  ];
  invalidBitdepth = monitorConfig [
    {
      output = "DP-1";
      bitdepth = "ten";
    }
  ];
  missingOutput = monitorConfig [ { mode = "preferred"; } ];
  invalidHibernate =
    (system {
      custom.system.power.suspendThenHibernate.hibernateDelaySec = -1;
    }).custom.system.power.suspendThenHibernate.hibernateDelaySec;
  validHibernateZero =
    (system {
      custom.system.power.suspendThenHibernate.hibernateDelaySec = 0;
    }).custom.system.power.suspendThenHibernate.hibernateDelaySec;
  invalidGeminiCount =
    (system { custom.services.ai.geminiKeyCount = 0; }).custom.services.ai.geminiKeyCount;
  monitorsWithWarnings = system {
    custom.desktop.hyprland = {
      enable = true;
      monitors = [
        {
          output = "DP-\"quoted";
          hdr = true;
          note = "metadata";
        }
        {
          output = "DP-2";
          hdr = true;
        }
      ];
    };
  };
  renderMonitors = import ../lib/hyprland-monitors.nix { inherit lib; };
  rendered = renderMonitors {
    monitors = monitorsWithWarnings.custom.desktop.hyprland.monitors;
    notifySend = "/bin/notify-send";
  };
  fallback = renderMonitors {
    monitors = [ ];
    notifySend = "/bin/notify-send";
  };
  escapedOutput = "output = ${builtins.toJSON "DP-\"quoted"}";
  specialOutput = "DP-\"quoted\\u0001" + builtins.fromJSON ''"\u000b"'' + "3";
  special = renderMonitors {
    monitors = [
      {
        output = specialOutput;
        mode = "mode\nwith\"quotes";
        position = "x\\y";
        scale = 1.5;
        bitdepth = 8;
        cm = "srgb\tcustom";
        sdrbrightness = 0.7;
        hdr = true;
      }
    ];
    notifySend = "/bin/notify-send";
  };

  # In addition to the isolated module checks above, verify that the actual
  # Hyprland Home Manager configuration consumes the shared renderer.
  desktopHost = self.nixosConfigurations.junixos.config;
  hostHyprland =
    desktopHost.home-manager.users.${desktopHost.custom.user}.wayland.windowManager.hyprland.extraConfig;
in
assert builtins.elem ../modules/nixos/hypr.nix systemModules;
assert builtins.elem ../modules/nixos/pkgs/browsers.nix systemModules;
assert builtins.elem ../modules/home-manager/hypr/hyprland.nix userModules;
assert !(builtins.elem ../modules/home-manager/default.nix userModules);
assert lib.all (path: builtins.baseNameOf path != "default.nix") (systemModules ++ userModules);
assert !headless.custom.desktop.enable && !headless.custom.desktop.wayland.enable;
assert headless.custom.system.power.suspendThenHibernate.hibernateDelaySec == 3600;
assert headless.custom.services.ai.geminiKeyCount == 10;
assert validHibernateZero == 0 && !(isValid invalidHibernate) && !(isValid invalidGeminiCount);
assert
  hypr.custom.desktop.enable
  && hypr.custom.desktop.wayland.enable
  && hypr.custom.desktop.fonts.enable;
assert x11.custom.desktop.enable && !x11.custom.desktop.wayland.enable;
assert !x11.custom.desktop.hyprland.enable && x11.custom.desktop.fonts.enable;
assert x11Home.gtk.enable && x11Home.qt.enable;
assert x11Home.programs.kitty.enable && x11Home.programs.rofi.enable;
assert x11Home.home.pointerCursor.enable && !x11Home.home.pointerCursor.hyprcursor.enable;
assert !(x11Home.gtk.gtk3.extraConfig ? gtk-decoration-layout);
assert !x11Home.services.mako.enable;
assert x11System.services.xserver.windowManager.i3.enable && !x11System.programs.hyprland.enable;
assert !x11System.xdg.portal.enable && x11System.xdg.portal.extraPortals == [ ];
assert !x11System.xdg.portal.xdgOpenUsePortal;
assert desktopHost.xdg.portal.enable;
assert builtins.elem desktopHost.programs.hyprland.portalPackage
  desktopHost.xdg.portal.extraPortals;
assert desktopHost.xdg.portal.xdgOpenUsePortal;
assert wayland.custom.desktop.enable && !wayland.custom.desktop.hyprland.enable;
assert waylandHome.services.mako.enable;
assert waylandHome.systemd.user.services ? mpvpaper;
assert !(waylandHome.systemd.user.services ? mpvpaper-autopause);
assert hyprHome.gtk.gtk3.extraConfig.gtk-decoration-layout == ":";
assert hyprHome.home.pointerCursor.hyprcursor.enable && hyprHome.services.mako.enable;
assert
  standaloneHome.gtk.enable && standaloneHome.qt.enable && standaloneHome.programs.kitty.enable;
assert standaloneHome.programs.rofi.enable && standaloneHome.services.mako.enable;
assert standaloneHome.home.pointerCursor.hyprcursor.enable;
assert builtins.length standaloneHome.custom.theme.palette.ansi == 16;
assert desktopOptOut.custom.desktop.hyprland.enable && !desktopOptOut.custom.desktop.enable;
assert !desktopOptOut.custom.desktop.fonts.enable && !optOutHome.gtk.enable;
assert !independent.custom.desktop.gaming.enable && independent.services.flatpak.enable;
assert !independent.custom.hardware.amdgpu.enable && independent.services.lact.enable;
assert isValid validMonitors;
assert (builtins.head validMonitors).mode == "preferred";
assert (builtins.head validMonitors).bitdepth == null;
assert !(isValid invalidScale) && !(isValid invalidBitdepth) && !(isValid missingOutput);
assert lib.any (lib.hasInfix "extra fields are not rendered: note") monitorsWithWarnings.warnings;
assert lib.any (lib.hasInfix "multiple HDR outputs") monitorsWithWarnings.warnings;
assert lib.hasInfix escapedOutput rendered.layout && lib.hasInfix escapedOutput rendered.hdrToggle;
assert lib.hasInfix "bitdepth = 10" rendered.hdrToggle;
assert lib.hasInfix ''cm = hdr_on and "hdr" or "srgb"'' rendered.hdrToggle;
assert lib.hasInfix ''output = ""'' fallback.layout && fallback.hdrToggle == "";
assert lib.hasInfix ''output = "DP-\"quoted\\u0001\0113"'' special.layout;
assert lib.hasInfix ''output = "DP-\"quoted\\u0001\0113"'' special.hdrToggle;
assert lib.hasInfix ''output = "DP-2"'' hostHyprland;
assert lib.hasInfix ''mode = "2560x1440@180"'' hostHyprland;
assert lib.hasInfix ''output = "DP-1"'' hostHyprland;
assert lib.hasInfix ''cm = hdr_on and "hdr" or "srgb"'' hostHyprland;
assert lib.hasInfix ''hl.bind(mainMod .. " + SHIFT + H", toggle_hdr)'' hostHyprland;
pkgs.runCommand "desktop-modularity-options" { nativeBuildInputs = [ pkgs.lua5_5 ]; } ''
  lua ${./hyprland-monitors.lua} \
    ${pkgs.writeText "monitor-layout.lua" special.layout} \
    ${pkgs.writeText "monitor-hdr.lua" special.hdrToggle}
  mkdir -p "$out"
''
