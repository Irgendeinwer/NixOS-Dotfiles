{config, pkgs, ...}:

{
fonts= {
	packages = with pkgs; [
		noto-fonts
		noto-fonts-cjk
		noto-fonts-emoji

		(nerdfonts.override { fonts = [ "FiraCode" "DroidSansMono" ]; })
	];
	fontconfig = {
		defaultFonts = {
      			serif = [ "Noto Serif" ];
      			sansSerif = [ "Noto Sans" ];
      			monospace = [ "Fira Code" ];
    		};
	};
};
}
