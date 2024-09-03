{config, pkgs, ...}:

{
fonts= {
	packages = with pkgs; [
		#noto-fonts
		noto-fonts-cjk
		noto-fonts-emoji
		vegur

		(nerdfonts.override { fonts = [ "Noto" "FiraCode" ]; })
	];
	fontconfig = {
		defaultFonts = {
      			serif = [ "Noto Nerd Font Serif" ];
      			sansSerif = [ "Noto Nerd Font Sans" ];
      			monospace = [ "Fira Code Nerd Font Mono" "Noto Nerd Font Sans Mono"];
    		};
	};
};
}
