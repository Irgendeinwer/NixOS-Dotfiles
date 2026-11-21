{
  nixpkgs,
  pkgs,
  self,
}:
let
  inherit (nixpkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;

  evalTailscale =
    extraConfig:
    (lib.nixosSystem {
      inherit system;
      modules = [
        ../modules/services/tailscale.nix
        {
          networking.hostName = "tailscale-test";
          system.stateVersion = "26.11";
        }
        extraConfig
      ];
    }).config;

  disabled = evalTailscale { };
  client = evalTailscale {
    custom.services.tailscale.enable = true;
  };
  server = evalTailscale {
    networking.nftables.enable = true;
    systemd.network.enable = true;
    custom.services.tailscale = {
      enable = true;
      shieldsUp = false;
      allowedTCPPorts = [ 4533 ];
      allowedUDPPorts = [ 22000 ];
    };
  };
  customClient = evalTailscale {
    custom.services.tailscale = {
      enable = true;
      openFirewall = false;
      acceptDns = true;
      peers = {
        "junixsrv.internal" = "100.64.0.10";
        "junixsrv-ts" = "100.64.0.10";
      };
    };
  };
  selfPeer = evalTailscale {
    custom.services.tailscale = {
      enable = true;
      peers.tailscale-test = "100.64.0.10";
    };
  };
  localhostPeer = evalTailscale {
    custom.services.tailscale = {
      enable = true;
      peers.localhost = "100.64.0.10";
    };
  };
  badIpPeer = evalTailscale {
    custom.services.tailscale = {
      enable = true;
      peers."junixsrv.internal" = "not-an-ip";
    };
  };

  clientFlags = [
    "--accept-dns=false"
    "--shields-up=true"
  ];
  serverFlags = [
    "--accept-dns=false"
    "--shields-up=false"
  ];
  dnsClientFlags = [
    "--accept-dns=true"
    "--shields-up=true"
  ];

  hasFailedAssertion =
    prefix: cfg: lib.any (a: !a.assertion && lib.hasPrefix prefix a.message) cfg.assertions;

  desktopHost = self.nixosConfigurations.junixos.config;
  laptopHost = self.nixosConfigurations.junixbook.config;
  serverHost = self.nixosConfigurations.junixsrv.config;
  laptopKnownHosts = laptopHost.programs.ssh.knownHosts."junixsrv.local".extraHostNames;
  laptopSubstituters = laptopHost.nix.settings.substituters;
  untrustedManual =
    cfg:
    let
      ts = cfg.services.tailscale;
    in
    ts.enable
    && ts.authKeyFile == null
    && ts.useRoutingFeatures == "none"
    && ts.disableTaildrop
    && !(builtins.elem ts.interfaceName cfg.networking.firewall.trustedInterfaces);
in
assert !disabled.services.tailscale.enable;
assert !(builtins.hasAttr "tailscale0" disabled.networking.firewall.interfaces);
assert untrustedManual client;
assert client.services.tailscale.openFirewall;
assert builtins.elem 41641 client.networking.firewall.allowedUDPPorts;
assert client.services.tailscale.extraSetFlags == clientFlags;
assert !(client.systemd.services.tailscaled.environment ? TS_DEBUG_FIREWALL_MODE);
assert client.systemd.services.tailscaled-set.serviceConfig.RemainAfterExit;
assert builtins.elem "multi-user.target" client.systemd.services.tailscaled-set.wantedBy;
assert builtins.elem "tailscaled.service" client.systemd.services.tailscaled-set.partOf;
assert untrustedManual server;
assert server.services.tailscale.openFirewall;
assert server.services.tailscale.extraSetFlags == serverFlags;
assert server.systemd.services.tailscaled.environment.TS_DEBUG_FIREWALL_MODE == "nftables";
assert !server.systemd.network.config.networkConfig.ManageForeignRoutingPolicyRules;
assert !server.systemd.network.config.networkConfig.ManageForeignRoutes;
assert server.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [ 4533 ];
assert server.networking.firewall.interfaces.tailscale0.allowedUDPPorts == [ 22000 ];
assert !customClient.services.tailscale.openFirewall;
assert !(builtins.elem 41641 customClient.networking.firewall.allowedUDPPorts);
assert customClient.services.tailscale.extraSetFlags == dnsClientFlags;
assert builtins.elem "junixsrv.internal" customClient.networking.hosts."100.64.0.10";
assert builtins.elem "junixsrv-ts" customClient.networking.hosts."100.64.0.10";
assert hasFailedAssertion "custom.services.tailscale.peers:" selfPeer;
assert hasFailedAssertion "custom.services.tailscale.peers:" localhostPeer;
assert hasFailedAssertion "custom.services.tailscale.peers:" badIpPeer;
assert !desktopHost.custom.services.tailscale.enable && !desktopHost.services.tailscale.enable;
assert untrustedManual laptopHost && untrustedManual serverHost;
assert laptopHost.services.tailscale.openFirewall && serverHost.services.tailscale.openFirewall;
assert laptopHost.services.tailscale.extraSetFlags == clientFlags;
assert serverHost.services.tailscale.extraSetFlags == serverFlags;
assert laptopHost.custom.system.remoteBuilder.host == "junixsrv.local";
assert laptopHost.custom.system.remoteBuilder.tailscaleHost == "junixsrv.internal";
assert builtins.elem "junixsrv.internal" laptopHost.networking.hosts."100.110.103.47";
assert builtins.elem "junixsrv.internal" laptopKnownHosts;
assert builtins.elem "100.110.103.47" laptopKnownHosts;
assert builtins.elem "http://junixsrv.internal:5000?priority=50" laptopSubstituters;
assert serverHost.systemd.services.tailscaled.environment.TS_DEBUG_FIREWALL_MODE == "nftables";
assert !serverHost.systemd.network.config.networkConfig.ManageForeignRoutingPolicyRules;
assert !serverHost.systemd.network.config.networkConfig.ManageForeignRoutes;
assert serverHost.services.openssh.enable && serverHost.services.openssh.openFirewall;
assert serverHost.services.openssh.listenAddresses == [ ];
assert serverHost.services.harmonia.cache.enable;
assert serverHost.services.harmonia.cache.settings.bind == "[::]:5000";
assert builtins.elem 5000 serverHost.networking.firewall.allowedTCPPorts;
pkgs.runCommand "tailscale-host-options" { } ''
  mkdir -p "$out"
''
