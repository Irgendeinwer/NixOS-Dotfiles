{
  nixpkgs,
  sopsModule,
  system,
  pkgs,
}:
let
  evalRemoteBuilder =
    { enable, offload }:
    nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        sopsModule
        { options.custom.user = nixpkgs.lib.mkOption { type = nixpkgs.lib.types.str; }; }
        ../modules/nixos/remote-builder.nix
        {
          networking.hostName = "remote-builder-test";
          custom.user = "julian";
          system.stateVersion = "26.11";
          services.resolved.enable = true;
          custom.system.remoteBuilder = {
            inherit enable offload;
          };
        }
      ];
    };

  disabled = evalRemoteBuilder {
    enable = false;
    offload = true;
  };
  cacheOnly = evalRemoteBuilder {
    enable = true;
    offload = false;
  };
  offloading = evalRemoteBuilder {
    enable = true;
    offload = true;
  };
  cacheUrl = "http://junixsrv.local:5000";
in
assert disabled.config.nix.buildMachines == [ ];
assert !(builtins.elem cacheUrl disabled.config.nix.settings.substituters);
assert !(builtins.hasAttr "nix_builder_ssh_key" disabled.config.sops.secrets);
assert cacheOnly.config.nix.buildMachines == [ ];
assert !cacheOnly.config.nix.distributedBuilds;
assert builtins.elem cacheUrl cacheOnly.config.nix.settings.substituters;
assert !(builtins.hasAttr "nix_builder_ssh_key" cacheOnly.config.sops.secrets);
assert offloading.config.nix.distributedBuilds;
assert builtins.length offloading.config.nix.buildMachines == 1;
assert (builtins.head offloading.config.nix.buildMachines).hostName == "junixsrv.local";
assert builtins.hasAttr "nix_builder_ssh_key" offloading.config.sops.secrets;
assert
  offloading.config.sops.secrets.nix_builder_ssh_key.sopsFile == (
    if builtins.pathExists (../secrets + "/users/julian.yaml") then
      ../secrets + "/users/julian.yaml"
    else
      ../secrets/common.yaml
  );
pkgs.runCommand "remote-builder-option-combinations" { } ''
  mkdir -p "$out"
''
