{ pkgs, inputs, ... }:
{
  imports = [
    ./plugins/default.nix
    ./options.nix
    ./theme.nix
  ];

  programs.nixvim = {
    enable = true;
    nixpkgs.source = inputs.nixpkgs;
  };

  environment.systemPackages = with pkgs; [
    nixd
    rust-analyzer
    nixfmt
    rustfmt
  ];
}
