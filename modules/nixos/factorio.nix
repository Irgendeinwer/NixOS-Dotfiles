{ config, lib, pkgs, ... }:

{
  # 1. Define options
  options.gaming.factorioServer = {
    enable = lib.mkEnableOption "the Factorio dedicated server";

    user = lib.mkOption {
      type = lib.types.str;
      description = "The user who can start/stop the server without a password.";
      example = "julian";
    };
  };

  # 2. Apply configuration
  config = lib.mkIf config.gaming.factorioServer.enable {
    # Allow the proprietary Factorio headless server package
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "factorio-headless" ];

    services.factorio = {
      enable = true;
      openFirewall = true;
      # Disables the license/account check so your friend can join
      requireUserVerification = false; 
    };

    # Prevent the service from starting automatically on system boot
    systemd.services.factorio.wantedBy = lib.mkForce [ ];

    # Allow the specified user to manage the server without a sudo password
    security.sudo.extraRules = [
      {
        users = [ config.gaming.factorioServer.user ];
        commands = [
          { command = "/run/current-system/sw/bin/systemctl start factorio"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/systemctl stop factorio"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/systemctl status factorio"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/systemctl restart factorio"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];
  };
}
