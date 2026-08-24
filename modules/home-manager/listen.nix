{ pkgs, ... }:

let
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

    text = builtins.readFile ./listen.sh;
  };
in
{
  home.packages = [ listen ];
}

