{
  nixpkgs,
  pkgs,
  self,
}:
let
  inherit (nixpkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  sampleServerId = "7CFNTQM-IMTJBHJ-3UWRDIU-ZGQJFR6-VCXZ3NB-XUH3KZO-N52ITXR-LAIYUAU";

  evalSyncthing =
    {
      hostName ? "syncthing-test",
      extraConfig ? { },
    }:
    (lib.nixosSystem {
      inherit system;
      modules = [
        {
          options.custom.user = lib.mkOption {
            type = lib.types.str;
            default = "irgendeinwer";
          };
        }
        ../modules/services/syncthing.nix
        ../modules/services/navidrome.nix
        {
          networking.hostName = hostName;
          system.stateVersion = "26.11";
        }
        extraConfig
      ];
    }).config;

  disabled = evalSyncthing { };

  laptopUnpaired = evalSyncthing {
    hostName = "junixbook";
    extraConfig.custom.services.syncthing = {
      enable = true;
      junixsrvDeviceId = null;
    };
  };

  laptopPaired = evalSyncthing {
    hostName = "junixbook";
    extraConfig.custom.services.syncthing = {
      enable = true;
      junixsrvDeviceId = sampleServerId;
      junixsrvTailscaleHost = "junixsrv.internal.";
    };
  };

  desktopPaired = evalSyncthing {
    hostName = "junixos";
    extraConfig.custom.services.syncthing = {
      enable = true;
      junixsrvDeviceId = sampleServerId;
      junixsrvTailscaleHost = "fd7a:115c:a1e0::10";
    };
  };

  serverPaired = evalSyncthing {
    hostName = "junixsrv";
    extraConfig = {
      boot.isContainer = true;
      custom.services = {
        syncthing = {
          enable = true;
          junixsrvDeviceId = sampleServerId;
        };
        navidrome.enable = true;
      };
    };
  };

  badId = evalSyncthing {
    extraConfig.custom.services.syncthing = {
      enable = true;
      junixsrvDeviceId = "not-a-device-id";
    };
  };

  expectedFolderNames = [
    "Documents"
    "E-Books"
    "Music"
    "Schule-26-27"
  ];
  allPairedDevices = [
    "junixos"
    "junixbook"
    "junixsrv"
    "MobileF6"
  ];
  musicPairedDevices = [
    "junixos"
    "junixsrv"
    "MobileF6"
  ];

  hasFailedAssertion =
    prefix: cfg: lib.any (a: !a.assertion && lib.hasPrefix prefix a.message) cfg.assertions;

  pinnedServerId = "QAMX456-2AVIPJR-CY2WCZS-VGHETIN-WW5WFEX-BDOBA2T-MSPXG2U-VZLNPQN";
  desktopHost = self.nixosConfigurations.junixos.config;
  laptopHost = self.nixosConfigurations.junixbook.config;
  serverHost = self.nixosConfigurations.junixsrv.config;
  laptopSync = laptopHost.services.syncthing.settings;
  unpairedFolders = laptopUnpaired.services.syncthing.settings.folders;
  pairedFolders = laptopPaired.services.syncthing.settings.folders;
  serverFolders = serverPaired.services.syncthing.settings.folders;
in
assert !disabled.services.syncthing.enable;
assert laptopUnpaired.services.syncthing.enable;
assert laptopUnpaired.services.syncthing.openDefaultPorts;
assert builtins.elem 22000 laptopUnpaired.networking.firewall.allowedTCPPorts;
assert builtins.elem 21027 laptopUnpaired.networking.firewall.allowedUDPPorts;
assert builtins.elem 22000 laptopUnpaired.networking.firewall.allowedUDPPorts;
assert laptopUnpaired.services.syncthing.dataDir == "/home/irgendeinwer";
assert laptopUnpaired.services.syncthing.configDir == "/home/irgendeinwer/.config/syncthing";
assert laptopUnpaired.services.syncthing.guiAddress == "127.0.0.1:8384";
assert laptopUnpaired.services.syncthing.overrideDevices;
assert laptopUnpaired.services.syncthing.overrideFolders;
assert laptopUnpaired.services.syncthing.settings.options.urAccepted == -1;
assert laptopUnpaired.services.syncthing.settings.options.localAnnounceEnabled;
assert laptopUnpaired.systemd.services.syncthing.serviceConfig.PrivateUsers;
assert !(builtins.hasAttr "junixsrv" laptopUnpaired.services.syncthing.settings.devices);
assert builtins.attrNames unpairedFolders == expectedFolderNames;
assert !(builtins.hasAttr "#Noice" unpairedFolders);
assert unpairedFolders.Documents.enable;
assert unpairedFolders."Schule-26-27".enable;
assert unpairedFolders."E-Books".enable;
assert !unpairedFolders.Music.enable;
assert !unpairedFolders.Music.ignorePerms;
assert laptopPaired.services.syncthing.settings.devices.junixsrv.id == sampleServerId;
assert
  laptopPaired.services.syncthing.settings.devices.junixsrv.addresses == [
    "tcp://junixsrv.local:22000"
    "quic://junixsrv.local:22000"
    "tcp://junixsrv.internal:22000"
    "quic://junixsrv.internal:22000"
    "dynamic"
  ];
assert pairedFolders.Documents.devices == allPairedDevices;
assert pairedFolders."Schule-26-27".devices == allPairedDevices;
assert pairedFolders."E-Books".devices == allPairedDevices;
assert pairedFolders.Music.devices == musicPairedDevices;
assert !pairedFolders.Music.enable;
assert
  desktopPaired.services.syncthing.settings.devices.junixsrv.addresses == [
    "tcp://junixsrv.local:22000"
    "quic://junixsrv.local:22000"
    "tcp://[fd7a:115c:a1e0::10]:22000"
    "quic://[fd7a:115c:a1e0::10]:22000"
    "dynamic"
  ];
assert desktopPaired.services.syncthing.settings.folders.Music.enable;
assert serverPaired.services.syncthing.settings.devices.junixsrv.addresses == [ "dynamic" ];
assert !serverPaired.systemd.services.syncthing.serviceConfig.PrivateUsers;
assert serverFolders.Documents.enable;
assert serverFolders."Schule-26-27".enable;
assert serverFolders."E-Books".enable;
assert serverFolders.Music.enable;
assert serverFolders.Music.ignorePerms;
assert serverFolders."Schule-26-27".versioning.type == "staggered";
assert serverFolders."E-Books".versioning.type == "trashcan";
assert serverFolders.Music.versioning == null;
assert hasFailedAssertion "custom.services.syncthing.junixsrvDeviceId:" badId;
assert desktopHost.services.syncthing.enable;
assert laptopHost.services.syncthing.enable;
assert serverHost.services.syncthing.enable;
assert desktopHost.services.syncthing.settings.devices.junixsrv.id == pinnedServerId;
assert laptopSync.devices.junixsrv.id == pinnedServerId;
assert serverHost.services.syncthing.settings.devices.junixsrv.id == pinnedServerId;
assert builtins.elem "tcp://junixsrv.internal:22000" laptopSync.devices.junixsrv.addresses;
assert builtins.elem "quic://junixsrv.internal:22000" laptopSync.devices.junixsrv.addresses;
assert !(builtins.hasAttr "#Noice" desktopHost.services.syncthing.settings.folders);
assert !(builtins.hasAttr "#Noice" laptopSync.folders);
assert !(builtins.hasAttr "#Noice" serverHost.services.syncthing.settings.folders);
assert desktopHost.services.syncthing.settings.folders.Music.enable;
assert desktopHost.services.syncthing.settings.folders.Music.devices == musicPairedDevices;
assert !laptopSync.folders.Music.enable;
assert laptopSync.folders.Documents.devices == allPairedDevices;
assert serverHost.services.syncthing.settings.folders.Music.enable;
assert serverHost.services.syncthing.settings.folders.Music.ignorePerms;
assert !serverHost.systemd.services.syncthing.serviceConfig.PrivateUsers;
pkgs.runCommand "syncthing-host-options" { } ''
  mkdir -p "$out"
''
