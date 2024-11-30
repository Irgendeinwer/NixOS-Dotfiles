{ pkgs, ...}:

{
  fonts= {
    packages = with pkgs; [
	#noto-fonts
	noto-fonts-cjk-sans
	noto-fonts-emoji
	vegur
	quicksand
	fira-code-nerdfont
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
