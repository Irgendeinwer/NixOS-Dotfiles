{
  config,
  inputs,
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

  environment.systemPackages = with pkgs; [
    git
    htop
    tmux
    tree
  ];

  home-manager = {
    extraSpecialArgs = { inherit inputs; };
    users = {
      "${config.custom.user}" = import ./home.nix;
    };
  };

  # --------------------custom options---------------

  custom = {
    system = {
      container.enable = true;
      # Server GC is managed via nix.gc + min-free rather than nh's ~/dotfiles setup
      nh.enable = false;
    };

    services = {
      buildServer.enable = true;
    };
  };

  # Initial NixOS release version for state compatibility
  system.stateVersion = "26.11";
}
