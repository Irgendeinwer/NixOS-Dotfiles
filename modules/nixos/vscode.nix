{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.vscode;
in
{
  options.custom.desktop.vscode = {
    enable = lib.mkEnableOption "VS Code editor";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfreePackages = [ "vscode" ];

    environment.systemPackages = [
      pkgs.vscode-fhs
    ];
  };
}
