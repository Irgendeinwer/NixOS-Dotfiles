{ pkgs, ... }:
{
  imports = [
    ./plugins/default.nix
    ./options.nix
    # ./keybinds.nix
  ];

  programs.nixvim = {
    enable = true;
    colorschemes.gruvbox = {
        enable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    nixd
    rust-analyzer
  ];
}
