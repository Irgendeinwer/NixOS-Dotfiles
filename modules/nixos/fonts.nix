{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.fonts;
in
{
  options.custom.desktop.fonts = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.custom.desktop.hyprland.enable;
      description = "Enable desktop system fonts and fontconfig defaults.";
    };
  };

  config = lib.mkIf cfg.enable {
    fonts = {
      packages = with pkgs; [
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        vegur
        quicksand
        nerd-fonts.fira-code
      ];
      fontconfig = {
        defaultFonts = {
          serif = [ "Noto Nerd Font Serif" ];
          sansSerif = [ "Noto Nerd Font Sans" ];
          monospace = [
            "Fira Code Nerd Font Mono"
            "Noto Nerd Font Sans Mono"
          ];
        };
      };
    };
  };
}
