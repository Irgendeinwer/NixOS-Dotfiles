{
  config,
  inputs,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules
  ];

  # Host identification
  networking.hostName = "junixbook";
  system.stateVersion = "24.05";

  # Corporate/School SSL Certificate
  environment.etc."ssl/certs/iserv.pem".source = ../../assets/iserv.pem;

  # Laptop-specific system packages
  environment.systemPackages = with pkgs; [
    networkmanagerapplet
    scrcpy
  ];

  home-manager = {
    extraSpecialArgs = { inherit inputs; };
    users = {
      "${config.custom.user}" = import ./home.nix;
    };
  };

  # --------------------custom options---------------

  custom = {
    system = {
      kernel = "latest";
      boot = {
        silent.enable = true;
        secureboot.enable = true;
      };
      security.hardening.enable = true;
      power = {
        upower.enable = true;
        ignorePowerKey = true;
      };
    };

    hardware.bluetooth.enable = true;

    desktop = {
      hyprland = {
        enable = true;
        monitors = [
          {
            output = "eDP-1";
            mode = "preferred";
            position = "auto";
            scale = 1;
          }
        ];
      };
      greetd.enable = true;
      sound.enable = true;
      gaming.enable = true;
      tools.enable = true;
      browsers.enable = true;
      messaging.enable = true;
      media.enable = true;
      flexing.enable = true;
      office.enable = true;
    };

    services = {
      syncthing.enable = true;
      playerctl.enable = true;
    };
  };

  # --------------------custom options end-----------
}
