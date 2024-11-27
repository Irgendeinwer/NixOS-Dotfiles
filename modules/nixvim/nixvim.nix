{ pkgs, inputs, config, ... }:
{
  imports = [
	# ./plugins/default.nix
	# ./options.nix
	# ./keybinds.nix
  ];


  programs.nixvim = {
	enable = true;
	colorschemes.gruvbox = {
		enable = true;
	};
  };
}
