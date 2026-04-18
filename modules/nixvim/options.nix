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
    };

    clipboard = {
      register = "unnamedplus";
      providers.wl-copy.enable = true;
    };

    globals.mapleader = " ";
  };
}
