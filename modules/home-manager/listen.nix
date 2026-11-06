{
  lib,
  osConfig ? null,
  pkgs,
  ...
}:

let
  mediaEnabled = if osConfig != null then (osConfig.custom.desktop.media.enable or false) else true;

  mpvWithScripts = pkgs.mpv.override {
    scripts = with pkgs.mpvScripts; [
      mpris
      uosc
      thumbfast
    ];
  };

  listen = pkgs.writeShellApplication {
    name = "listen";

    runtimeInputs = with pkgs; [
      fd
      fzf
      gnused
      coreutils
      mpvWithScripts
      xdg-user-dirs
    ];

    excludeShellChecks = [
      "SC2016"
      "SC2154"
    ];

    text = builtins.readFile ./scripts/listen.sh;
  };
in
lib.mkIf mediaEnabled {
  home.packages = [ listen ];
}
