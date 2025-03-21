{ config, lib, ... }:

{
  options = {
    greetd = {
      enable = lib.mkEnableOption "greetd";
      command = lib.mkOption {
        type = lib.types.str;
        default = "dbus-launch --exit-with-session Hyprland && hyprlock";
      };
    };
    getty = {
      enable = lib.mkEnableOption "getty";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf config.greetd.enable {
      services.greetd = {
        enable = true;
        settings = rec {
          initial_session = {
            command = "${config.greetd.command}";
            user = "julian";
          };
          default_session = initial_session;
        };
      };
    })
    (lib.mkIf config.getty.enable {
      services.getty.autologinUser = "julian";
    })
  ];
}
