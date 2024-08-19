{config, pkgs, ...}:

{
fonts= {
	packages = with pkgs; [
		noto-fonts
		noto-fonts-cjk
		noto-fonts-emoji

		nerdfonts
	];
	fontconfig = {
		defaultFonts = {
      			serif = [ "Noto Serif" ];
      			sansSerif = [ "Noto Sans" ];
      			monospace = [ "Meslo LG Mono Nerd Font" ];
    		};
	};
};
}
