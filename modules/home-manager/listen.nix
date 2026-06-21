{ pkgs, ... }:

let
  listen = pkgs.writeShellApplication {
    name = "listen";

    runtimeInputs = with pkgs; [
      fd
      fzf
      gnused
      coreutils
      mpv
      xdg-user-dirs
    ];

    excludeShellChecks = [ "SC2016" ];

    text = builtins.readFile ./scripts/listen.sh;
  };
in
{
  home.packages = [ listen ];
}
