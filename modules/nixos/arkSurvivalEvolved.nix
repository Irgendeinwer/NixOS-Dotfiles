{ config, pkgs, lib, ... }:
{
  # 1. Define options
  options.gaming.arkServer = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the ARK: Survival Evolved dedicated server.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      description = "The user who can start/stop the server without a password.";
      example = "julian";
    };
  };

  # 2. Apply configuration
  config = lib.mkIf config.gaming.arkServer.enable {
    nixpkgs.config.allowUnfree = true;

    environment.systemPackages = with pkgs; [
      steamcmd
      steam-run
      mcrcon
    ];

    users.users.ark = {
      isSystemUser = true;
      home = "/var/lib/ark";
      createHome = true;
      group = "ark";
    };
    users.groups.ark = {};

    networking.firewall = {
      allowedUDPPorts = [ 7777 7778 27015 ];
      allowedTCPPorts = [ 27020 ];
    };

    systemd.services.ark-server = {
      description = "ARK: Survival Evolved Dedicated Server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      
      restartIfChanged = false;
      stopIfChanged = false;

      serviceConfig = {
        User = "ark";
        Group = "ark";
        StateDirectory = "ark";
        WorkingDirectory = "/var/lib/ark";
        LimitNOFILE = 100000;
        TimeoutStartSec = "1h";
        
        ExecStartPre = let
          steamcmd = "${pkgs.steamcmd}/bin/steamcmd";
        in "${steamcmd} +force_install_dir /var/lib/ark +login anonymous +app_update 376030 validate +quit";

        ExecStart = let
          steamRun = "${pkgs.steam-run}/bin/steam-run";
          serverBin = "/var/lib/ark/ShooterGame/Binaries/Linux/ShooterGameServer";
          
          settings = [
            "listen"
            "ServerPVE=True"                   # Force PvE mode to enable Gamma permissions
            "SessionName=ILikeFemboys"
            "ServerPassword=SigmaRizzlerFemboy"
            "ServerAdminPassword=ILikeNixOSAndFemboys"
            "RCONEnabled=True"
            "RCONPort=27020"
            "AllowSharedConnections=True"
            "ShowMapPlayerLocation=True"
            "ServerCrosshair=True"
            "AllowThirdPersonPlayer=True"
            "EnablePvEGamma=True"
            "EnablePvPGamma=True"
            "AlwaysAllowStructurePickup=True"
            "StructurePickupHoldDuration=0.5"
            "DifficultyOffset=1.0"
            "OverrideOfficialDifficulty=5.0" 
            "TamingSpeedMultiplier=3.0"
            "HarvestAmountMultiplier=3.0"
            "XPMultiplier=2.0"
            "BabyMatureSpeedMultiplier=10.0"
            "EggHatchSpeedMultiplier=10.0"
            # "bRawSockets=True"
	    "PlayerCharacterNameTagDistance=200000.0" # Massive distance for nameplates
            "bFloatingNames=True"                     # Ensure names are enabled
          ];
          
          args = "?" + (builtins.concatStringsSep "?" settings);
          flags = "-server -log -NoBattlEye -UseAllAvailableCores -high -noundermeshcheck";
          
        in "${steamRun} ${serverBin} TheIsland${args} ${flags}";

        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    security.sudo.extraRules = [
      {
        users = [ config.gaming.arkServer.user ];
        commands = [
          { command = "/run/current-system/sw/bin/systemctl start ark-server"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/systemctl stop ark-server"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/systemctl status ark-server"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/systemctl restart ark-server"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];
  };
}
