{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules
  ];

  # Host identification
  networking.hostName = "junixbook";
  system.stateVersion = "24.05";

  # ssh-ng forwards the client's core setting; this also applies locally.
  nix.settings.cores = 3;

  # Corporate/School SSL Certificate
  environment.etc."ssl/certs/iserv.pem".source = ../../assets/iserv.pem;

  # Laptop-specific system packages
  environment.systemPackages = with pkgs; [
    networkmanagerapplet
    scrcpy
  ];

  # Host-specific daemons
  services.fstrim.enable = true;

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
      remoteBuilder = {
        enable = true;
        maxJobs = 3;
        tailscaleHost = "junixsrv.internal";
        tailscaleSubstituter = true;
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
      planner.enable = true;
      flexing.enable = true;
      office.enable = true;
    };

    services = {
      tailscale = {
        enable = true;
        mtu = 1180;
        peers = {
          "junixsrv.internal" = "100.110.103.47";
          "music.junixsrv.internal" = "100.110.103.47";
          "tasks.junixsrv.internal" = "100.110.103.47";
          "cal.junixsrv.internal" = "100.110.103.47";
        };
      };
      syncthing.enable = true;
      playerctl.enable = true;
    };
  };

  # --------------------custom options end-----------
}
