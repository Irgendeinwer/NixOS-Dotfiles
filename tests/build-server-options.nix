{
  nixpkgs,
  sopsModule,
  system,
  pkgs,
}:
let
  evalBuildServer =
    {
      enable,
      nightly,
      notify,
    }:
    nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        sopsModule
        ../modules/nixos/container.nix
        ../modules/services/build-server.nix
        {
          networking.hostName = "junixsrv";
          system.stateVersion = "26.11";
          custom.system.container.enable = false;
          custom.services.buildServer = {
            inherit enable;
            nightly.enable = nightly;
            nightly.notify.enable = notify;
          };
        }
      ];
    };

  disabled = evalBuildServer {
    enable = false;
    nightly = true;
    notify = true;
  };
  nightlyDisabled = evalBuildServer {
    enable = true;
    nightly = false;
    notify = true;
  };
  notifyDisabled = evalBuildServer {
    enable = true;
    nightly = true;
    notify = false;
  };
  notifyEnabled = evalBuildServer {
    enable = true;
    nightly = true;
    notify = true;
  };
in
assert !(builtins.hasAttr "nix_nightly_webhook" disabled.config.sops.secrets);
assert !(builtins.hasAttr "nix_nightly_ssh_key" disabled.config.sops.secrets);
assert !(builtins.hasAttr "nix_nightly_webhook" nightlyDisabled.config.sops.secrets);
assert !(builtins.hasAttr "nix_nightly_ssh_key" nightlyDisabled.config.sops.secrets);
assert !(builtins.hasAttr "nix_nightly_webhook" notifyDisabled.config.sops.secrets);
assert builtins.hasAttr "nix_nightly_ssh_key" notifyDisabled.config.sops.secrets;
assert builtins.hasAttr "nix_nightly_webhook" notifyEnabled.config.sops.secrets;
assert notifyEnabled.config.sops.secrets.nix_nightly_webhook.key == "nix_nightly_webhook";
assert
  notifyEnabled.config.systemd.services.nix-nightly-update.serviceConfig.StateDirectoryMode == "0700";
let
  execStart = notifyEnabled.config.systemd.services.nix-nightly-update.serviceConfig.ExecStart;
in
pkgs.runCommand "build-server-option-combinations" { } ''
  test -x ${execStart}
  mkdir -p "$out"
''
