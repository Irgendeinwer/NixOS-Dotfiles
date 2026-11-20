{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.tailscale;
  iface = config.services.tailscale.interfaceName;
  hasInterfacePorts = cfg.allowedTCPPorts != [ ] || cfg.allowedUDPPorts != [ ];
  peerHosts = lib.zipAttrsWith (_: lib.concatLists) (
    lib.mapAttrsToList (host: ip: { ${ip} = [ host ]; }) cfg.peers
  );
  validHostname = name: name != "localhost" && builtins.match "[^[:space:]]+" name != null;
  validIp = ip: builtins.match "[0-9a-fA-F:.]+" ip != null;
in
{
  options.custom.services.tailscale = {
    enable = lib.mkEnableOption "Tailscale private mesh VPN";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the Tailscale WireGuard UDP port in the firewall for direct LAN
        and WAN peer connections. Does not mark the Tailscale interface as
        trusted.
      '';
    };

    shieldsUp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Block incoming tailnet connections (--shields-up). Keep enabled on
        roaming clients; disable on servers that expose services over the
        tailnet.
      '';
    };

    acceptDns = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Accept MagicDNS and tailnet resolver settings (--accept-dns). Disabled
        by default to preserve host and captive-portal DNS.
      '';
    };

    allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Additional TCP ports opened only on the Tailscale interface.";
    };

    allowedUDPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Additional UDP ports opened only on the Tailscale interface.";
    };

    peers = lib.mkOption {
      type = lib.types.attrsOf lib.types.nonEmptyStr;
      default = { };
      example = {
        "junixsrv.internal" = "100.64.0.10";
      };
      description = ''
        Static hostname-to-Tailscale-IP mappings added to /etc/hosts so
        clients can use stable names without enabling global MagicDNS.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all validHostname (builtins.attrNames cfg.peers);
        message = "custom.services.tailscale.peers: hostnames must be non-empty, contain no whitespace, and not be \"localhost\".";
      }
      {
        assertion = !(builtins.elem config.networking.hostName (builtins.attrNames cfg.peers));
        message = "custom.services.tailscale.peers: must not override this host's own networking.hostName (${config.networking.hostName}).";
      }
      {
        assertion = lib.all validIp (builtins.attrValues cfg.peers);
        message = "custom.services.tailscale.peers: values must be literal IPv4 or IPv6 addresses.";
      }
    ];

    services.tailscale = {
      enable = true;
      inherit (cfg) openFirewall;
      disableTaildrop = lib.mkDefault true;
      useRoutingFeatures = lib.mkDefault "none";
      # Pass explicit booleans in both states so toggling an option reconciles
      # tailscaled's persistent preferences instead of leaving sticky state.
      extraSetFlags = [
        "--accept-dns=${lib.boolToString cfg.acceptDns}"
        "--shields-up=${lib.boolToString cfg.shieldsUp}"
      ];
    };

    networking = {
      hosts = peerHosts;
      firewall.interfaces.${iface} = lib.mkIf hasInterfacePorts {
        inherit (cfg) allowedTCPPorts allowedUDPPorts;
      };
    };

    # Keep systemd-networkd from flushing Tailscale's policy routing rules
    # (5210..5270) and table 52 routes on reload or DHCP renewal.
    systemd.network.config.networkConfig = lib.mkIf config.systemd.network.enable {
      ManageForeignRoutingPolicyRules = lib.mkDefault false;
      ManageForeignRoutes = lib.mkDefault false;
    };

    systemd.services = {
      # Use native nf_tables netlink on nftables hosts (including nspawn guests
      # without CAP_SYS_MODULE for xtables/nft_compat).
      tailscaled.environment = lib.mkIf config.networking.nftables.enable {
        TS_DEBUG_FIREWALL_MODE = lib.mkDefault "nftables";
      };

      # Upstream only sets wantedBy = [ "tailscaled.service" ] without
      # RemainAfterExit, so live nixos-rebuild switches that change
      # extraSetFlags without restarting tailscaled would otherwise skip it.
      tailscaled-set = {
        wantedBy = [ "multi-user.target" ];
        partOf = [ "tailscaled.service" ];
        serviceConfig.RemainAfterExit = true;
      };
    };
  };
}
