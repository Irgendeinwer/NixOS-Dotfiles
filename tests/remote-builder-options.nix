{
  nixpkgs,
  sopsModule,
  system,
  pkgs,
}:
let
  inherit (nixpkgs) lib;
  evalRemoteBuilder =
    {
      enable ? true,
      offload ? true,
      resolved ? true,
      lix ? false,
      host ? "junixsrv.local",
      extraConfig ? { },
    }:
    lib.nixosSystem {
      inherit system;
      modules = [
        sopsModule
        { options.custom.user = lib.mkOption { type = lib.types.str; }; }
        ../modules/nixos/remote-builder.nix
        {
          networking.hostName = "remote-builder-test";
          custom.user = "julian";
          system.stateVersion = "26.11";
          nix.package = if lix then pkgs.lixPackageSets.stable.lix else pkgs.nix;
          services.resolved.enable = resolved;
          custom.system.remoteBuilder = {
            inherit enable offload host;
          };
        }
        extraConfig
      ];
    };

  disabled = evalRemoteBuilder {
    enable = false;
    resolved = false;
  };
  cacheOnly = evalRemoteBuilder { offload = false; };
  offloading = evalRemoteBuilder { };
  avahiCpp = evalRemoteBuilder { resolved = false; };
  avahiLix = evalRemoteBuilder {
    resolved = false;
    lix = true;
    host = "junixsrv.local.";
    extraConfig.custom.system.remoteBuilder.extraHostAliases = [
      "junixsrv.internal"
      "music.junixsrv.internal."
    ];
  };
  invalidAlias = evalRemoteBuilder {
    resolved = false;
    extraConfig.custom.system.remoteBuilder.extraHostAliases = [ "localhost" ];
  };
  avahiCache = evalRemoteBuilder {
    resolved = false;
    lix = true;
    offload = false;
  };
  nonLocal = evalRemoteBuilder {
    resolved = false;
    host = "builder.example.invalid";
  };
  otherBuilder = evalRemoteBuilder {
    offload = false;
    extraConfig.nix = {
      distributedBuilds = true;
      buildMachines = [
        {
          hostName = "other.example.invalid";
          systems = [ system ];
        }
      ];
      settings.connect-timeout = 30;
    };
  };
  tailscaleFallback = evalRemoteBuilder {
    extraConfig = {
      imports = [ ../modules/services/tailscale.nix ];
      custom.services.tailscale = {
        enable = true;
        peers."junixsrv.internal" = "100.64.0.10";
      };
      custom.system.remoteBuilder = {
        tailscaleHost = "junixsrv.internal.";
        tailscaleSubstituter = true;
      };
    };
  };
  tailscaleIpv6 = evalRemoteBuilder {
    offload = false;
    extraConfig.custom.system.remoteBuilder = {
      tailscaleHost = "fd7a:115c:a1e0::10";
      tailscaleSubstituter = true;
      tailscaleSubstituterPriority = 60;
    };
  };
  missingTailscaleHost = evalRemoteBuilder {
    extraConfig.custom.system.remoteBuilder.tailscaleSubstituter = true;
  };
  duplicateTailscaleHost = evalRemoteBuilder {
    extraConfig.custom.system.remoteBuilder.tailscaleHost = "junixsrv.local";
  };
  isBuilderAssertion = a: !a.assertion && lib.hasPrefix "custom.system.remoteBuilder:" a.message;
  hasFailedAssertion = host: lib.any isBuilderAssertion host.config.assertions;
  cacheUrl = "http://junixsrv.local:5000";
  tailscaleCacheUrl = "http://junixsrv.internal:5000?priority=50";
  tailscaleIpv6Url = "http://[fd7a:115c:a1e0::10]:5000?priority=60";
  mdnsUnit = "remote-builder-mdns.service";
  hasMdns = host: builtins.hasAttr "remote-builder-mdns" host.config.systemd.services;
  ordersAfterMdns =
    service: builtins.elem mdnsUnit service.after && builtins.elem mdnsUnit service.wants;
  sshConfig = pkgs.writeText "remote-builder-ssh.conf" offloading.config.programs.ssh.extraConfig;
  tsExtraSsh = tailscaleFallback.config.programs.ssh.extraConfig;
  tsSshConfig = pkgs.writeText "remote-builder-ts-ssh.conf" tsExtraSsh;
  tsExtraHosts = tailscaleFallback.config.programs.ssh.knownHosts."junixsrv.local".extraHostNames;
  lixSyncScript = avahiLix.config.system.activationScripts.remoteBuilderHosts.text;
in
assert disabled.config.nix.buildMachines == [ ];
assert !(builtins.elem cacheUrl disabled.config.nix.settings.substituters);
assert !(builtins.hasAttr "nix_builder_ssh_key" disabled.config.sops.secrets);
assert !(hasMdns disabled);
assert cacheOnly.config.nix.buildMachines == [ ];
assert !cacheOnly.config.nix.distributedBuilds;
assert builtins.elem cacheUrl cacheOnly.config.nix.settings.substituters;
assert !(builtins.hasAttr "nix_builder_ssh_key" cacheOnly.config.sops.secrets);
assert builtins.hasAttr "junixsrv.local" cacheOnly.config.programs.ssh.knownHosts;
assert !(lib.hasInfix "IdentityAgent none" cacheOnly.config.programs.ssh.extraConfig);
assert otherBuilder.config.nix.distributedBuilds;
assert (builtins.head otherBuilder.config.nix.buildMachines).hostName == "other.example.invalid";
assert otherBuilder.config.nix.settings.connect-timeout == 30;
assert builtins.elem cacheUrl tailscaleFallback.config.nix.settings.substituters;
assert builtins.elem tailscaleCacheUrl tailscaleFallback.config.nix.settings.substituters;
assert builtins.length tailscaleFallback.config.nix.buildMachines == 1;
assert (builtins.head tailscaleFallback.config.nix.buildMachines).hostName == "junixsrv.local";
assert builtins.elem "junixsrv.internal" tsExtraHosts;
assert builtins.elem "100.64.0.10" tsExtraHosts;
assert builtins.elem tailscaleIpv6Url tailscaleIpv6.config.nix.settings.substituters;
assert hasFailedAssertion missingTailscaleHost;
assert hasFailedAssertion duplicateTailscaleHost;
assert hasFailedAssertion invalidAlias;
assert lib.hasInfix "--alias junixsrv.internal" lixSyncScript;
assert lib.hasInfix "--alias music.junixsrv.internal" lixSyncScript;
assert offloading.config.nix.distributedBuilds;
assert builtins.length offloading.config.nix.buildMachines == 1;
assert (builtins.head offloading.config.nix.buildMachines).hostName == "junixsrv.local";
assert (builtins.head offloading.config.nix.buildMachines).sshUser == "nixbuilder";
assert builtins.hasAttr "nix_builder_ssh_key" offloading.config.sops.secrets;
assert
  offloading.config.sops.secrets.nix_builder_ssh_key.sopsFile == (
    if builtins.pathExists (../secrets + "/users/julian.yaml") then
      ../secrets + "/users/julian.yaml"
    else
      ../secrets/common.yaml
  );
assert !(hasMdns offloading);
assert !(hasMdns nonLocal);
assert hasMdns avahiCpp && hasMdns avahiLix && hasMdns avahiCache;
assert builtins.elem cacheUrl avahiLix.config.nix.settings.substituters;
assert ordersAfterMdns avahiCpp.config.systemd.services.nix-daemon;
assert ordersAfterMdns avahiLix.config.systemd.services."nix-daemon@";
assert ordersAfterMdns avahiCache.config.systemd.services."nix-daemon@";
# The early socket must not depend on Avahi and create a basic.target cycle.
assert !(builtins.elem mdnsUnit avahiLix.config.systemd.sockets.nix-daemon.after);
assert !(builtins.elem mdnsUnit avahiLix.config.systemd.sockets.nix-daemon.wants);
assert avahiLix.config.environment.etc.hosts.mode == "0644";
assert avahiLix.config.system.activationScripts.remoteBuilderHosts.deps == [ "etc" ];
assert lib.hasInfix "--restore" avahiLix.config.system.activationScripts.remoteBuilderHosts.text;
assert avahiLix.config.systemd.services.remote-builder-mdns.serviceConfig.Type == "notify";
assert avahiLix.config.systemd.services.remote-builder-mdns.serviceConfig.Restart == "always";
assert
  avahiLix.config.systemd.services.remote-builder-mdns.serviceConfig.RuntimeDirectoryPreserve
  == "yes";
assert lib.hasInfix mdnsUnit avahiLix.config.systemd.units."nix-daemon@.service".text;
pkgs.runCommand "remote-builder-option-combinations"
  {
    nativeBuildInputs = [
      pkgs.openssh
      pkgs.gnugrep
    ];
  }
  ''
    # Inspect effective SSH configuration without making a network connection.
    export SSH_AUTH_SOCK=/tmp/test-user-agent
    ssh -G -F ${sshConfig} nixbuilder@junixsrv.local > builder
    grep -Fx 'identityagent none' builder
    grep -Fx 'identitiesonly yes' builder
    grep -Fx 'connecttimeout 3' builder
    for user in julian root; do
      ssh -G -F ${sshConfig} "$user@junixsrv.local" > admin
      if grep -Ex 'identityagent none|identitiesonly yes|connecttimeout 3' admin; then
        echo "builder-only SSH options applied to $user" >&2
        exit 1
      fi
    done
    ssh -G -F ${sshConfig} nixbuilder@other.example.invalid > other
    if grep -Fx 'identityagent none' other; then
      echo 'builder-only SSH options applied to another host' >&2
      exit 1
    fi
    for host in junixsrv.local junixsrv.internal 100.64.0.10; do
      ssh -G -F ${tsSshConfig} "nixbuilder@$host" > ts-builder
      grep -Fx 'identityagent none' ts-builder
      grep -Fx 'identitiesonly yes' ts-builder
      grep -Fx 'connecttimeout 3' ts-builder
    done
    ssh -G -F ${tsSshConfig} julian@junixsrv.internal > ts-admin
    if grep -Ex 'identityagent none|identitiesonly yes|connecttimeout 3' ts-admin; then
      echo 'builder-only SSH options applied to julian over Tailscale' >&2
      exit 1
    fi
    mkdir -p "$out"
  ''
