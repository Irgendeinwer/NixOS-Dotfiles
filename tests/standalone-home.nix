{
  inputs,
  pkgs,
}:
let
  inherit (inputs.nixpkgs) lib;
  standalonePkgs = import inputs.nixpkgs {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  standalone = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = standalonePkgs;
    extraSpecialArgs = { inherit inputs; };
    modules = [
      ../modules/home-manager
      {
        home.username = "test";
        home.homeDirectory = "/home/test";
        home.stateVersion = "24.05";
        custom.desktop.media.royalPresetProfile = "calm";
      }
    ];
  };
  home = standalone.config;
in
assert home.gtk.enable && home.qt.enable && home.programs.kitty.enable;
assert home.programs.rofi.enable && home.services.mako.enable;
assert home.wayland.windowManager.hyprland.enable;
assert lib.hasInfix ''output = ""'' home.wayland.windowManager.hyprland.extraConfig;
assert lib.hasInfix "rofi --capture" home.wayland.windowManager.hyprland.extraConfig;
assert lib.hasInfix "pulse" home.wayland.windowManager.hyprland.extraConfig;
assert home.xdg.configFile ? "junix-plan/config.json";
assert home.xdg.configFile ? "dankcal/gruvbox-theme.json";
assert home.systemd.user.services ? junix-plan-daemon;
assert home.systemd.user.services ? dcal;
assert lib.hasInfix "dcal toggle" home.wayland.windowManager.hyprland.extraConfig;
assert home.programs.zen-browser.enable && home.programs.zen-browser.profiles == { };
assert builtins.length home.custom.theme.palette.ansi == 16;
assert lib.hasInfix "/calm/" (
  toString home.xdg.dataFile."projectM/presets/Custom/royal-mashup-remix.milk".source
);
# Force the complete Home Manager activation derivation and its assertions.
assert lib.hasSuffix ".drv" home.home.activationPackage.drvPath;
pkgs.runCommand "standalone-home-options" { } ''
  mkdir -p "$out"
''
