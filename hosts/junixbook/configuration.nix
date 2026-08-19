{ inputs, pkgs, ... }:

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

  # Laptop power management & behavior
  services.logind.settings.Login.HandlePowerKey = "ignore";
  services.upower.enable = true;

  # Laptop-specific system packages
  environment.systemPackages = with pkgs; [
    libreoffice
    networkmanagerapplet
    scrcpy
  ];

  home-manager = {
    extraSpecialArgs = { inherit inputs; };
    users = {
      "julian" = import ./home.nix;
    };
  };

  # --------------------custom options---------------

  custom = {
    system.kernel = "latest";

    hardware.bluetooth.enable = true;

    desktop = {
      greetd.enable = true;
      sound.enable = true;
      gaming.enable = true;
    };

    services = {
      syncthing.enable = true;
      printing.enable = true;
      playerctl.enable = true;
    };
  };

  # --------------------custom options end-----------
}
