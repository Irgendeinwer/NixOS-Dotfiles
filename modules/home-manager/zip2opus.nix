{ pkgs, ... }:

let
  zip2opus = pkgs.writeShellApplication {
    name = "zip2opus";

    runtimeInputs = with pkgs; [
      ffmpeg
      opustags
      unar
      coreutils
      findutils
      gnused
      gnugrep
      gawk
    ];

    excludeShellChecks = [
      # Values are piped through sed on purpose (trim/sanitize helpers)
      "SC2001"
      # load_tags and already_imported set globals their callers read
      "SC2154"
    ];

    text = builtins.readFile ./scripts/zip2opus.sh;
  };
in
{
  home.packages = [ zip2opus ];
}
