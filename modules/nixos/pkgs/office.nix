{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.office;
in
{
  options.custom.desktop.office = {
    enable = lib.mkEnableOption "office productivity suite and dictionaries (LibreOffice, Hunspell)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      libreoffice
      hunspell
      hunspellDicts.de_DE
      hunspellDicts.en_US
      hyphenDicts.de_DE
      hyphenDicts.en_US
    ];
  };
}
