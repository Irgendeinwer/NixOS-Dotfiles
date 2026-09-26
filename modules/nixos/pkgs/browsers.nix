{
  config,
  lib,
  pkgs,
  inputs,
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
      inputs.zen-browser.packages.x86_64-linux.default
      tor-browser
      firefox
      ungoogled-chromium
    ];
  };
}
