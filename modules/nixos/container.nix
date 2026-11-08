{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.system.container;
  isLix = config.nix.package.pname == "lix";

  tarballExtraCommands = pkgs.writeShellScript "container-tarball-extra" ''
    mkdir -p boot proc sys dev etc/ssh root var/lib
    install -d -m 1777 var/tmp
  '';

  # Retain the legacy C++ Nix compatibility path. Lix uses its namespace probe
  # and socket-activated instances without this filter; do not disable working
  # user namespaces just to attach a workaround it does not need.
  withoutUserNs = pkgs.callPackage ../../pkgs/without-userns.nix { };

  nixDaemonBin = lib.getExe' config.nix.package.out "nix-daemon";
in
{
  options.custom.system.container = {
    enable = lib.mkEnableOption "standalone NixOS systemd-nspawn container with self-managed Nix store";

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGmS2msoj3OiB3TKZ//iANhCnjXItQDC2VpXSzhcuraW"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp7q+GwPQeRaejko5ZdzwrpK/VsOhQsVpBTdZSLAuxz"
      ];
      description = "SSH public keys authorized for root and the primary user inside the container.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optional (!isLix) {
      assertion = config.nix.daemonUser == "root";
      message = "custom.system.container: the legacy C++ Nix without-userns wrapper requires nix.daemonUser = \"root\".";
    };

    # Keep PAM sessions, including non-login root SSH commands, on the daemon
    # so they use the same scheduling and sandbox policy as remote builds.
    environment.sessionVariables.NIX_REMOTE = lib.mkDefault "daemon";

    boot = {
      # Implies boot.isContainer = true while suppressing specialfs remounts of
      # /proc, /run, /dev, /dev/pts, and /dev/shm inside systemd-nspawn.
      isNspawnContainer = true;
      # Keep /sbin/init updated on `nixos-rebuild switch` so container reboots
      # start the active NixOS generation instead of the initial tarball build.
      loader.initScript.enable = true;
    };

    nix.settings = {
      # Containers lack /dev/kvm unless explicitly passed through; omit kvm and
      # nixos-test while preserving benchmark, big-parallel, and gccarch-*.
      system-features = lib.mkForce (
        [
          "benchmark"
          "big-parallel"
        ]
        ++ lib.optionals (pkgs.stdenv.hostPlatform ? gcc.arch) (
          [ "gccarch-${pkgs.stdenv.hostPlatform.gcc.arch}" ]
          ++ map (x: "gccarch-${x}") (
            lib.systems.architectures.inferiors.${pkgs.stdenv.hostPlatform.gcc.arch} or [ ]
          )
        )
      );
      # nixpkgs compiles a pasta path into Lix even though the raw upstream
      # setting defaults to empty. Disable it without /dev/net/tun so fixed-
      # output derivations do not enter an unusable private network namespace.
      pasta-path = lib.mkIf isLix "";
    };

    # Ignore the host's /etc/resolv.conf and acquire a LAN address via
    # systemd-networkd. Do not inherit LAN DHCP/RA DNS inside macvlan
    # containers: if the LAN DNS server runs on the parent container host
    # (e.g. rgl at 192.168.100.2), Linux macvlan isolation drops host <-> guest
    # packets and every DNS lookup times out.
    networking = {
      nftables.enable = true;
      useDHCP = false;
      useHostResolvConf = false;
      useNetworkd = true;
      nameservers = lib.mkDefault [
        "9.9.9.9"
        "149.112.112.112"
        "2620:fe::fe"
        "2620:fe::9"
      ];
    };

    services.resolved = {
      enable = true;
      settings.Resolve.MulticastDNS = false;
    };

    systemd.network = {
      enable = true;
      networks."20-container-lan" = {
        matchConfig.Name = [
          "mv-*"
          "host0"
          "eth*"
          "en*"
        ];
        DHCP = "yes";
        networkConfig.IPv6AcceptRA = true;
        dhcpV4Config.UseDNS = false;
        dhcpV6Config.UseDNS = false;
        ipv6AcceptRAConfig.UseDNS = false;
      };
    };

    # Advertise <hostname>.local on the LAN via mDNS (IPv4 only; glibc/nsncd
    # strips scope IDs from fe80:: link-local IPv6 mDNS answers).
    services.avahi = {
      enable = true;
      openFirewall = true;
      settings = {
        server.use-ipv6 = false;
        publish = {
          disable-publishing = false;
          publish-addresses = true;
          publish-workstation = true;
        };
      };
    };

    # Keep sshd running (rather than socket-activated) for low-latency remote
    # nix-daemon builds and administration.
    services.openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = false;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };

    users.users = {
      root.openssh.authorizedKeys.keys = cfg.authorizedKeys;
      ${config.custom.user}.openssh.authorizedKeys.keys = cfg.authorizedKeys;
    };

    systemd.services = {
      # Populate /nix/var/nix/db and the system profile on first boot from the
      # bootstrap tarball before nix-daemon starts accepting build requests.
      register-nix-paths = {
        description = "Register Nix Store Paths";
        unitConfig = {
          DefaultDependencies = false;
          ConditionPathExists = "/nix-path-registration";
        };
        wantedBy = [ "sysinit.target" ];
        before = [
          "sysinit.target"
          "shutdown.target"
          "nix-daemon.socket"
          "nix-daemon.service"
        ];
        after = [ "local-fs.target" ];
        conflicts = [ "shutdown.target" ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${lib.getExe' config.nix.package.out "nix-store"} --load-db < /nix-path-registration
          rm /nix-path-registration

          ${lib.getExe' config.nix.package.out "nix-env"} -p /nix/var/nix/profiles/system --set /run/current-system
        '';
      };

      # Preserve the legacy wrapper when selecting C++ Nix. The default Lix
      # 2.95 path serves nix-daemon@ instances and probes namespace support;
      # its normal build-dir is /nix/var/nix/b, not the client's TMPDIR. NixOS
      # already sets sandbox-fallback=false. Leave that path unmodified.
      nix-daemon = lib.mkIf (!isLix) {
        environment.TMPDIR = "/var/tmp";
        serviceConfig.ExecStart = [
          ""
          "${withoutUserNs}/bin/without-userns ${nixDaemonBin} --daemon"
        ];
      };
    };

    # Build a self-contained rootfs archive via:
    #   nix build .#nixosConfigurations.<host>.config.system.build.tarball
    system.build.tarball = pkgs.callPackage "${pkgs.path}/nixos/lib/make-system-tarball.nix" {
      fileName = "nixos-container-${config.networking.hostName}-${pkgs.stdenv.hostPlatform.system}";
      storeContents = [
        {
          object = config.system.build.toplevel;
          symlink = "/nix/var/nix/profiles/system";
        }
      ];
      contents = [
        {
          source = "${config.system.build.toplevel}/init";
          target = "/sbin/init";
        }
        {
          source = "${config.system.build.toplevel}/etc/os-release";
          target = "/etc/os-release";
        }
      ];
      extraCommands = toString tarballExtraCommands;
    };
  };
}
