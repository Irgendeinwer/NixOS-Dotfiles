{ lib, ... }:
{
  # Shared baseline applied to every host. Host files may still override
  # qt and home-manager (defaults, so per-host values win where set).
  # sessionVariables must stay plain: an mkDefault here is discarded
  # wholesale because sops.nix also defines this option.
  qt.enable = lib.mkDefault true;

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = lib.mkDefault true;
}
