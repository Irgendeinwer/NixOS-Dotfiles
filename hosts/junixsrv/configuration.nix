{
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../../modules
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking.hostName = "junixsrv";

  # Per-client parallelism; Debian's parent cgroup enforces the aggregate
  # CPU/memory budget for this container (see docs/recovery.md).
  nix.settings = {
    max-jobs = 3;
    cores = 3;
  };

  environment.systemPackages = with pkgs; [
    git
    htop
    tmux
    tree
  ];

  # --------------------custom options---------------

  custom = {
    system = {
      container.enable = true;
      # Server GC is managed via nix.gc + min-free rather than nh's ~/dotfiles setup
      nh.enable = false;
    };

    services = {
      # Kernel TUN inside nspawn; see docs/tailscale.md.
      tailscale = {
        enable = true;
        shieldsUp = false;
        mtu = 1180;
      };
      syncthing.enable = true;
      navidrome.enable = true;
      # Requires `vikunja_env` and `radicale_htpasswd` in secrets/junixsrv.yaml;
      # see docs/planner.md.
      planner.enable = true;
      # HTTPS landing page (:443, redirecting :80); see docs/portal.md.
      portal.enable = true;
      buildServer = {
        enable = true;
        nightly = {
          # Requires `nix_nightly_webhook` and `nix_private_deploy_key` in
          # secrets/junixsrv.yaml; see docs/recovery.md and docs/portal.md.
          notify.enable = true;
          extraDeployKeys."Irgendeinwer/nix-private" = "nix_private_deploy_key";
        };
      };
    };
  };

  # Initial NixOS release version for state compatibility
  system.stateVersion = "26.11";
}
