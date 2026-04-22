{ ... }:
{
  programs.nixvim.plugins.treesitter = {
    enable = true;

    highlight.enable = true;
    indent.enable = true;
  };
}
