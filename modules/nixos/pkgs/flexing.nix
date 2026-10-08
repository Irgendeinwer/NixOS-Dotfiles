{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.flexing;
in
{
  options.custom.desktop.flexing = {
    enable = lib.mkEnableOption "terminal toys, visualizers, and fetch tools (cmatrix, fastfetch, cava, etc.)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      cmatrix
      cbonsai
        uwufetch
      cava
      figlet
      lolcat
      fortune
      neo-cowsay
      pipes
      pipes-rs
      cool-retro-term
      activate-linux
    ];
  };
}
