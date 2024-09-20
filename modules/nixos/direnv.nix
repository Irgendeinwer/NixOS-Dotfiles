{ pkgs, ... }: 
{
  programs.direnv = {
	enable= true;
	silent = false;
	loadInNixShell = true;
	direnvrcExtra = "";
    	nix-direnv = {
		enable = true;
		package = pkgs.nix-direnv;
	};
  };
}
