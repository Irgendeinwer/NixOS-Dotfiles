{ inputs, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/base.nix

    ../../modules/nixos/lix.nix
    ../../modules/nixos/flakes.nix
    ../../modules/nixos/kernel.nix
    ../../modules/nixos/plymouth.nix
    ../../modules/nixos/greetd.nix
    ../../modules/nixos/sound.nix
    ../../modules/nixos/hypr.nix
    ../../modules/nixos/fonts.nix
    ../../modules/nixos/gaming.nix
    ../../modules/nixos/direnv.nix
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/android.nix
    ../../modules/nixos/nh.nix
    ../../modules/nixos/obs-studio.nix

    ../../modules/nixvim/nixvim.nix
    ../../modules/nixos/pkgs.nix
    ../../modules/services/services.nix
  ];

  # Host identification
  networking.hostName = "junixbook";

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

  networking.firewall.enable = false;

  home-manager = {
    extraSpecialArgs = { inherit inputs; };
    users = {
      "julian" = import ./home.nix;
    };
  };

  # --------------------custom options---------------

  custom = {
    system.kernel = "latest";

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
