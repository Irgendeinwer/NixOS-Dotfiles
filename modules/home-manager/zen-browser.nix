{
  inputs,
  lib,
  osConfig ? null,
  ...
}:
let
  browsersEnabled =
    if osConfig == null then true else (osConfig.custom.desktop.browsers.enable or false);
  defaultCaFile = ../../assets + "/junix-ca.pem";
  localCaCert =
    if osConfig != null then
      (
        if (osConfig.custom.system.security.localCa.enable or false) then
          (osConfig.custom.system.security.localCa.certificateFile or null)
        else
          null
      )
    else if builtins.pathExists defaultCaFile then
      defaultCaFile
    else
      null;
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
      Certificates = lib.mkIf (localCaCert != null) {
        ImportEnterpriseRoots = lib.mkDefault true;
        Install = [ (toString localCaCert) ];
      };
    };
  };
}
