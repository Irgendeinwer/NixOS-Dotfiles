{ pkgs, inputs, ... }:
{
  imports = [
    ./plugins/default.nix
    ./options.nix
  ];

  programs.nixvim = {
    enable = true;
    nixpkgs.source = inputs.nixpkgs;
    # Same scheme as the rest of the desktop (custom.theme.palette)
    colorschemes.gruvbox-material = {
      enable = true;
      settings = {
        background = "medium";
        foreground = "mix";
        enable_bold = 1;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    nixd
    rust-analyzer
    nixfmt
    rustfmt
  ];
}
