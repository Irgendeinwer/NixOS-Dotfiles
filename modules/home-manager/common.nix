{ lib, ... }:
{
  # Shared baseline applied to every host. Host files may still override
  # these (all defaults, so per-host values win where set).
  qt.enable = lib.mkDefault true;

  home.sessionVariables = lib.mkDefault {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = lib.mkDefault true;
}
