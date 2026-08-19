{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.desktop.greetd;
  gettyCfg = config.custom.desktop.getty;
in
{
  options.custom.desktop = {
    greetd = {
      enable = lib.mkEnableOption "greetd";
      command = lib.mkOption {
        type = lib.types.str;
        default = "start-hyprland";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = config.custom.user;
        description = "User to start session for";
      };
    };
    getty = {
      enable = lib.mkEnableOption "getty";
      user = lib.mkOption {
        type = lib.types.str;
        default = config.custom.user;
        description = "User to autologin";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = "${cfg.command}";
            user = cfg.user;
          };
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd ${cfg.command}";
            user = "greeter";
          };
        };
      };
    })
    (lib.mkIf gettyCfg.enable { services.getty.autologinUser = gettyCfg.user; })
  ];
}
