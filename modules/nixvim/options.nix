{ ... }:
{
  programs.nixvim = {
    opts = {
      number = true;
      shiftwidth = 2;
      tabstop = 2;
      softtabstop = 2;
      expandtab = true;
      smartindent = true;
      relativenumber = true;
      termguicolors = true;

      undofile = true;
      incsearch = true;
      scrolloff = 8;
      cursorline = true;
      signcolumn = "yes";
    };

    clipboard = {
      register = "unnamedplus";
      providers.wl-copy.enable = true;
    };

    globals.mapleader = " ";
  };
}
