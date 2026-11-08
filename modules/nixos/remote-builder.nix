{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.system.remoteBuilder;
  targetHost = lib.removeSuffix "." cfg.host;
  userName = config.custom.user;
  useAvahiMdns = lib.hasSuffix ".local" targetHost && !config.services.resolved.enable;
  userSecretsFile = ../../secrets + "/users/${userName}.yaml";
  builderKeyFile =
    if builtins.pathExists userSecretsFile then userSecretsFile else ../../secrets/common.yaml;
  avahiLibDir = "${lib.getLib pkgs.avahi}/lib";

  # Nix/Lix bypass nss-mdns. Both activation and the Avahi subscriber use
  # the same helper and lock to update /etc/hosts and its cached address.
  mdnsHostsSync = ./scripts/remote-builder-mdns.py;
  syncCommand = lib.escapeShellArgs [
    "${pkgs.python3}/bin/python3"
    "${mdnsHostsSync}"
    "--host"
    targetHost
  ];
  mdnsDependencies = {
    after = [ "remote-builder-mdns.service" ];
    wants = [ "remote-builder-mdns.service" ];
  };
in
{
  options.custom.system.remoteBuilder = {
    enable = lib.mkEnableOption "pull binary substitutions from, and optionally offload builds to, the LAN build server";

    offload = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Submit builds to the remote server over ssh-ng. When disabled, this
        module still configures the server as a binary substituter, but local
        build outputs are not automatically published to that server's cache.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "junixsrv.local";
      description = "Hostname or IP address of the remote Nix build server.";
    };

    hostPublicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFltIvsEVPVrWUfmBrEWFWuEeAncm5TdkBBcKL/FAUFz";
      description = "SSH host public key pinned in known_hosts (null falls back to accept-new).";
    };

    cachePublicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "junixsrv-1:hMSOLgD3WfEncRLN8nMULXRzks7yAoIEtqDNNnKkD4g=";
      description = "Public signing key from /var/lib/harmonia/cache-pub-key.pem on the build server.";
    };

    maxJobs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Maximum concurrent jobs sent to the remote server when offloading is enabled.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Only needed for offloading; a cache-only client never needs the user key.
    sops.secrets.nix_builder_ssh_key = lib.mkIf cfg.offload {
      sopsFile = builderKeyFile;
      key = "user_ssh_key";
      owner = "root";
      mode = "0400";
    };

    services.avahi = lib.mkIf useAvahiMdns {
      enable = lib.mkDefault true;
      openFirewall = lib.mkDefault true;
    };

    environment.etc = lib.mkIf useAvahiMdns {
      hosts.mode = "0644";
    };

    # setup-etc.pl recopies the static hosts file on every switch. Restore
    # the latest cached IP under the same lock used by mDNS callbacks.
    system.activationScripts.remoteBuilderHosts = lib.mkIf useAvahiMdns {
      deps = [ "etc" ];
      text = "${syncCommand} --restore";
    };

    systemd.services = {
      remote-builder-mdns = lib.mkIf useAvahiMdns {
        description = "Sync Avahi mDNS IPv4 record for ${targetHost} into /etc/hosts";
        wantedBy = [ "multi-user.target" ];
        after = [
          "dbus.service"
          "avahi-daemon.service"
        ];
        requires = [ "avahi-daemon.service" ];
        restartTriggers = [ config.environment.etc.hosts.source ];
        serviceConfig = {
          Type = "notify";
          NotifyAccess = "main";
          ExecStart =
            "${syncCommand} "
            + lib.escapeShellArgs [
              "--avahi-common"
              "${avahiLibDir}/libavahi-common.so.3"
              "--avahi-client"
              "${avahiLibDir}/libavahi-client.so.3"
            ];
          Restart = "always";
          RestartSec = "1s";
          RuntimeDirectory = "remote-builder";
          RuntimeDirectoryPreserve = "yes";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = true;
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
        };
      };

      nix-daemon = lib.mkIf useAvahiMdns mdnsDependencies;
      # Lix serves the Accept=yes socket through per-connection instances.
      # Order those services, not the early-boot socket (which would cycle
      # through sockets.target/basic.target and the Avahi service).
      "nix-daemon@" = lib.mkIf (useAvahiMdns && config.nix.package.pname == "lix") mdnsDependencies;
    };

    programs.ssh = lib.mkIf cfg.offload {
      knownHosts = lib.optionalAttrs (cfg.hostPublicKey != null) {
        ${targetHost}.publicKey = cfg.hostPublicKey;
      };
      # Bound SSH connection attempts away from the LAN and bypass agent hooks
      # only for build submissions; administrative logins keep their own defaults.
      extraConfig = ''
        Match host ${targetHost} user nixbuilder
          Port 22
          IdentitiesOnly yes
          IdentityAgent none
          ConnectTimeout 3
          ConnectionAttempts 1
          ServerAliveInterval 15
          ServerAliveCountMax 2
          ${lib.optionalString (cfg.hostPublicKey == null) "StrictHostKeyChecking accept-new"}
        Match all
      '';
    };

    nix = {
      # Do not force the global setting off when this server is cache-only;
      # another module may configure a different remote builder.
      distributedBuilds = lib.mkIf cfg.offload true;

      buildMachines = lib.optionals cfg.offload [
        {
          hostName = targetHost;
          protocol = "ssh-ng";
          sshUser = "nixbuilder";
          sshKey = config.sops.secrets.nix_builder_ssh_key.path;
          systems = [ "x86_64-linux" ];
          inherit (cfg) maxJobs;
          # Scheduling weight for this builder; tune against observed throughput.
          speedFactor = 2;
          supportedFeatures = [
            "benchmark"
            "big-parallel"
          ];
        }
      ];

      settings = {
        builders-use-substitutes = true;
        fallback = true;
        # This is global HTTP policy (max-connect-timeout in Lix), not only
        # the LAN cache. Let hosts override it for slow networks.
        connect-timeout = lib.mkDefault 3;
        substituters = lib.optionals (cfg.cachePublicKey != null) [
          "http://${targetHost}:5000"
        ];
        trusted-public-keys = lib.optionals (cfg.cachePublicKey != null) [
          cfg.cachePublicKey
        ];
      };
    };
  };
}
