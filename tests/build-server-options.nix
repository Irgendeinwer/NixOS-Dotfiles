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
      extraDeployKeys ? { },
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
            nightly = {
              enable = nightly;
              inherit extraDeployKeys;
              notify.enable = notify;
            };
          };
        }
      ];
    };

  disabled = evalBuildServer {
    enable = false;
    nightly = true;
    notify = true;
    extraDeployKeys."Irgendeinwer/nix-private" = "nix_private_deploy_key";
  };
  nightlyDisabled = evalBuildServer {
    enable = true;
    nightly = false;
    notify = true;
    extraDeployKeys."Irgendeinwer/nix-private" = "nix_private_deploy_key";
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
    extraDeployKeys."Irgendeinwer/nix-private" = "nix_private_deploy_key";
  };
  badRepoSlug = evalBuildServer {
    enable = true;
    nightly = true;
    notify = false;
    extraDeployKeys."Irgendeinwer/nix-private.git" = "nix_private_deploy_key";
  };
  hasFailedAssertion =
    prefix: cfg:
    nixpkgs.lib.any (a: !a.assertion && nixpkgs.lib.hasPrefix prefix a.message) cfg.assertions;

  privateSecret = "nix_nightly_deploy_Irgendeinwer_nix_private";
  statusRule = "d /var/lib/nix-nightly-status 0755 root root -";
in
assert !(builtins.hasAttr "nix_nightly_webhook" disabled.config.sops.secrets);
assert !(builtins.hasAttr "nix_nightly_ssh_key" disabled.config.sops.secrets);
assert !(builtins.hasAttr privateSecret disabled.config.sops.secrets);
assert !(builtins.hasAttr "nix_nightly_webhook" nightlyDisabled.config.sops.secrets);
assert !(builtins.hasAttr "nix_nightly_ssh_key" nightlyDisabled.config.sops.secrets);
assert !(builtins.hasAttr privateSecret nightlyDisabled.config.sops.secrets);
assert !(builtins.hasAttr "nix_nightly_webhook" notifyDisabled.config.sops.secrets);
assert builtins.hasAttr "nix_nightly_ssh_key" notifyDisabled.config.sops.secrets;
assert !(builtins.hasAttr privateSecret notifyDisabled.config.sops.secrets);
assert builtins.hasAttr "nix_nightly_webhook" notifyEnabled.config.sops.secrets;
assert builtins.hasAttr privateSecret notifyEnabled.config.sops.secrets;
assert notifyEnabled.config.sops.secrets.${privateSecret}.key == "nix_private_deploy_key";
assert notifyEnabled.config.sops.secrets.${privateSecret}.mode == "0400";
assert builtins.elem statusRule notifyEnabled.config.systemd.tmpfiles.rules;
assert hasFailedAssertion "custom.services.buildServer.nightly.extraDeployKeys:" badRepoSlug.config;
assert builtins.elem "nixbuilder" notifyEnabled.config.nix.settings.trusted-users;
assert notifyEnabled.config.sops.secrets.nix_nightly_webhook.mode == "0400";
assert !(builtins.hasAttr "nix-nightly-update" nightlyDisabled.config.systemd.services);
assert !(builtins.hasAttr "nix-nightly-update" nightlyDisabled.config.systemd.timers);
assert
  notifyEnabled.config.systemd.services.nix-nightly-update.serviceConfig.TimeoutStopSec == "40s";
assert !(notifyEnabled.config.systemd.services.nix-nightly-update.serviceConfig ? UMask);
assert !notifyEnabled.config.systemd.timers.nix-nightly-update.timerConfig.Persistent;
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
