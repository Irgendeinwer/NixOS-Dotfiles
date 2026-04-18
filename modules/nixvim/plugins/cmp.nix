{ ... }:
{
  programs.nixvim.plugins.cmp = {
    enable = true;
    autoEnableSources = true;
    settings = {
      sources = [
        { name = "nvim_lsp"; }
        { name = "path"; }
        { name = "buffer"; }
      ];
      mapping = {
        "<Tab>" = "cmp.mapping.confirm({ select = true })";
        "<Down>" = "cmp.mapping.select_next_item()";
        "<Up>" = "cmp.mapping.select_prev_item()";
      };
    };
  };
}
