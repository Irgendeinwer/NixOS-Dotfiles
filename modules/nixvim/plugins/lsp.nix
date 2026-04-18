{ ... }:
{
  programs.nixvim.plugins.lsp = {
    enable = true;
    servers = {
      nixd.enable = true;
      rust_analyzer = {
        enable = true;
        installCargo = false;
        installRustc = false;
        
        settings = {
          check = {
            command = "clippy";
          };
          procMacro = {
            enable = true;
          };
          cargo = {
            allFeatures = true;
          };
        };
      };
    };
    keymaps.lspBuf = {
      "gd" = "definition";
      "K" = "hover";
      "<leader>rn" = "rename";
      "<leader>ca" = "code_action"; 
    };
  };
}
