{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.syncthing;
  hostName = config.networking.hostName;
  managedHosts = [
    "junixos"
    "junixbook"
    "junixsrv"
  ];
  isManagedHost = builtins.elem hostName managedHosts;

  formatSyncHost =
    h:
    let
      trimmed = lib.removeSuffix "." h;
      unwrapped =
        if lib.hasPrefix "[" trimmed && lib.hasSuffix "]" trimmed then
          lib.removePrefix "[" (lib.removeSuffix "]" trimmed)
        else
          trimmed;
    in
    if lib.hasInfix ":" unwrapped then "[${unwrapped}]" else unwrapped;

  tsEndpoint = lib.mapNullable formatSyncHost cfg.junixsrvTailscaleHost;
  junixsrvAddresses =
    if hostName == "junixsrv" then
      [ "dynamic" ]
    else
      [
        "tcp://junixsrv.local:22000"
        "quic://junixsrv.local:22000"
      ]
      ++ lib.optionals (tsEndpoint != null) [
        "tcp://${tsEndpoint}:22000"
        "quic://${tsEndpoint}:22000"
      ]
      ++ [ "dynamic" ];

  configuredDevices = {
    junixos.id = "4MAINN2-ZRIWH6F-GU47MQP-4RZEUZX-E7OJJMU-H3HVRUF-2JLGKMI-AUP5CQQ";
    junixbook.id = "XVJL4SC-76BTLAU-7KBGIFQ-GLOYBAR-OGFVIBM-R7H3DZW-MT7YYMP-D4VUVAS";
    MobileF6.id = "3TDB3IH-BQSLKAR-CTF76VY-IWSYB3S-X2WMD4U-P5QFA23-RBKPITT-U7M3FA6";
  }
  // lib.optionalAttrs (cfg.junixsrvDeviceId != null) {
    junixsrv = {
      id = cfg.junixsrvDeviceId;
      addresses = junixsrvAddresses;
    };
  };

  activeDevices = builtins.attrNames configuredDevices;
  allDevices = [
    "junixos"
    "junixbook"
    "junixsrv"
    "MobileF6"
  ];
  musicDevices = [
    "junixos"
    "junixsrv"
    "MobileF6"
  ];

  staggeredVersioning = {
    type = "staggered";
    params = {
      cleanInterval = "3600"; # 1 hour
      maxAge = "7776000"; # 90 days
    };
  };
  trashcanVersioning = {
    type = "trashcan";
    params.cleanoutDays = "30";
  };

  mkFolder =
    {
      path,
      devices,
      versioning ? null,
      ignorePerms ? false,
    }:
    {
      enable = !isManagedHost || builtins.elem hostName devices;
      inherit path versioning ignorePerms;
      devices = lib.filter (d: builtins.elem d activeDevices) devices;
    };

  validDeviceId = id: builtins.match "[A-Z2-7]{7}(-[A-Z2-7]{7}){7}" id != null;
in
{
  options.custom.services.syncthing = {
    enable = lib.mkEnableOption "Syncthing file synchronization";

    user = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = config.custom.user;
      defaultText = lib.literalExpression "config.custom.user";
      description = "User account to run Syncthing under.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open Syncthing sync (TCP/UDP 22000) and local discovery (UDP 21027) ports in the firewall.";
    };

    junixsrvDeviceId = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = "QAMX456-2AVIPJR-CY2WCZS-VGHETIN-WW5WFEX-BDOBA2T-MSPXG2U-VZLNPQN";
      description = ''
        Syncthing device ID for junixsrv. Set to null to bootstrap a fresh
        server identity before pairing across hosts.
      '';
    };

    junixsrvTailscaleHost = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = config.custom.system.remoteBuilder.tailscaleHost or null;
      defaultText = lib.literalExpression "config.custom.system.remoteBuilder.tailscaleHost";
      description = "Optional Tailscale hostname or IP for direct remote Syncthing connections to junixsrv.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.junixsrvDeviceId == null || validDeviceId cfg.junixsrvDeviceId;
        message = "custom.services.syncthing.junixsrvDeviceId: must be a 56-character Base32 Syncthing device ID (XXXXXXX-...).";
      }
    ];

    services.syncthing = {
      enable = true;
      openDefaultPorts = cfg.openFirewall;
      group = "users";
      user = cfg.user;
      dataDir = "/home/${cfg.user}";
      configDir = "/home/${cfg.user}/.config/syncthing";
      # Local-only: the firewall does not expose the web GUI port (8384).
      guiAddress = "127.0.0.1:8384";
      overrideDevices = true;
      overrideFolders = true;
      settings = {
        options = {
          urAccepted = -1;
          localAnnounceEnabled = true;
        };
        devices = configuredDevices;
        folders = {
          Documents = mkFolder {
            path = "/home/${cfg.user}/Documents";
            devices = allDevices;
            versioning = staggeredVersioning;
          };
          "Schule-26-27" = mkFolder {
            path = "/home/${cfg.user}/Schule-26-27";
            devices = allDevices;
            versioning = staggeredVersioning;
          };
          Music = mkFolder {
            path = "/home/${cfg.user}/music";
            devices = musicDevices;
            # Keep synced files readable by Navidrome without broadcasting
            # permission-bit changes back to peers.
            ignorePerms = config.custom.services.navidrome.enable or false;
          };
          "E-Books" = mkFolder {
            path = "/home/${cfg.user}/E-Books";
            devices = allDevices;
            versioning = trashcanVersioning;
          };
        };
      };
    };

    systemd.services.syncthing.serviceConfig = lib.mkIf config.boot.isContainer {
      PrivateUsers = lib.mkForce false;
    };
  };
}
