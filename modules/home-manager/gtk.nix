{ pkgs, ... }:
{
  gtk = {
	enable = true;
	theme = {
		package = pkgs.gruvbox-gtk-theme;
		name = "gruvbox-gtk-theme";
	};
	
	iconTheme = {
		package = pkgs.gruvbox-plus-icons;
		name = "Gruvbox-Plus-Dark";
	};
	
	gtk3.extraConfig = {
                gtk-application-prefer-dark-theme = true;
                gtk-button-images = true;
                gtk-menu-images = true;
        };
        
	gtk4.extraConfig = {
               	gtk-application-prefer-dark-theme = true;
               	gtk-button-images = true;
               	gtk-menu-images = true;
        };
  };
}
