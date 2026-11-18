{
  inputs,
  lib,
  osConfig ? null,
  ...
}:
let
  browsersEnabled =
    if osConfig == null then true else (osConfig.custom.desktop.browsers.enable or false);
in
{
  imports = [ inputs.zen-browser.homeModules.default ];

  # Install and configure Zen through Home Manager instead of adding a second
  # copy to systemPackages. Existing browser profiles and Sync remain untouched
  # unless a host explicitly declares a profile.
  programs.zen-browser = {
    enable = lib.mkDefault browsersEnabled;
    policies = {
      DisableAppUpdate = lib.mkDefault true;
      DisableTelemetry = lib.mkDefault true;
    };
  };
}
