# Standalone user CLI tools, exposed via `pkgs.custom.*` and `flake.packages`.
# Add a new public script by placing `<name>.sh` or `<name>.py` in this
# directory and registering an entry below.
{
  lib ? pkgs.lib,
  pkgs,
}:
let
  inherit (import ../mk-script.nix { inherit lib pkgs; }) mkPythonScript mkShellScript;

  mpvWithScripts = pkgs.mpv.override {
    scripts = with pkgs.mpvScripts; [
      mpris
      uosc
      thumbfast
    ];
  };
in
{
  listen = mkShellScript {
    name = "listen";
    src = ./listen.sh;
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
    meta.description = "Interactive terminal music picker backed by fd, fzf, and mpv";
  };

  lrclib-upload = mkPythonScript {
    name = "lrclib-upload";
    src = ./lrclib-upload.py;
    runtimeInputs = [ pkgs.ffmpeg ];
    meta.description = "Batch lyric uploader for LRCLIB with proof-of-work solver";
  };

  zip2opus = mkShellScript {
    name = "zip2opus";
    src = ./zip2opus.sh;
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
    meta.description = "Archive-to-Opus music album importer and tagger";
  };
}
