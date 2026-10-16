{ lib, ... }:
{
  # Shared baseline applied to every host. Host files may still override
  # these (defaults, so per-host values win where set).
  # sessionVariables must stay plain: an mkDefault here is discarded
  # wholesale because sops.nix also defines this option.
  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = lib.mkDefault true;
}
