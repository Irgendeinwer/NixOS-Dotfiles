{config, pkgs, ...}:

{
fonts= {
	packages = with pkgs; [
		noto-fonts
		noto-fonts-cjk
		noto-fonts-emoji
		vegur

		(nerdfonts.override { fonts = [ "FiraCode" ]; })
	];
	fontconfig = {
		defaultFonts = {
      			serif = [ "Noto Serif" ];
      			sansSerif = [ "Noto Sans" ];
      			monospace = [ "Fira Code Nerd Font Mono" ];
    		};
	};
};
}
