{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.browsers;
in
{
  options.custom.desktop.browsers = {
    enable = lib.mkEnableOption "desktop web browsers (Zen Browser, Firefox, Ungoogled Chromium, Tor Browser)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      tor-browser
      firefox
      ungoogled-chromium
    ];
  };
}
