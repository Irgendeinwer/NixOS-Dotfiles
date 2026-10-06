{ pkgs, inputs, ... }:
{
  imports = [
    ./plugins/default.nix
    ./options.nix
  ];

  programs.nixvim = {
    enable = true;
    nixpkgs.source = inputs.nixpkgs;
    colorschemes.gruvbox = {
      enable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    nixd
    rust-analyzer
    nixfmt
    rustfmt
  ];
}
