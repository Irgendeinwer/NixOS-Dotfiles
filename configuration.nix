{inputs, config, pkgs, ... }:

{
  imports =
    [
	./hardware-configuration.nix
	inputs.home-manager.nixosModules.home-manager
	./modules/flakes.nix
	./modules/greetd.nix
	./modules/sound.nix
	./modules/fonts.nix
	./modules/gaming.nix
	./modules/samba.nix
	./modules/flexing.nix
	./modules/streaming.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "junixos"; 

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  console.keyMap = "de";

  users.users.julian = {
    isNormalUser = true;
    description = "Julian Lindner";
    extraGroups = [ "networkmanager" "wheel" "kvm" "input" "libvirtd" ];
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
	wget
	curl
	kitty
	wofi
	mako
	libnotify
	dunst
	wl-clipboard
	xdg-desktop-portal-hyprland
	xdg-desktop-portal-gtk
	dconf
	firefox
	tor-browser
	obsidian
	waybar
	swww
	btop
	easyeffects
	openrgb
	gparted
	vlc
	celluloid
	prismlauncher
	zip
	unzip
	traceroute
	hyprshot
	whois
	dig
	telegram-desktop
	qimgv
	polkit
	polkit_gnome
	#polkit-kde-agent
	thefuck
	bat
	python3
	yt-dlp
	youtube-music
	obs-studio
];

users.defaultUserShell = pkgs.zsh;
environment.shells = with pkgs; [ zsh ];
programs.zsh.enable = true;

#services.hardware.openrgb.enable = true;

xdg = {
	portal = {
		enable = true;
		xdgOpenUsePortal = true;
		extraPortals = [
			pkgs.xdg-desktop-portal-hyprland
			pkgs.xdg-desktop-portal-gtk
		];
	};
};

programs = {
	hyprland.enable = true;
	neovim = {
		enable = true;
		defaultEditor = true;
	};
	kdeconnect.enable = true;
};

security.polkit.enable = true;

programs.mtr.enable = true;
programs.gnupg.agent = {
	enable = true;
        enableSSHSupport = true;
};

hardware = {
	graphics = {
		enable = true;
		enable32Bit = true;
	};
};

services.openssh.enable = true;

networking.firewall.enable = false;


home-manager = {
	extraSpecialArgs = {inherit inputs;};
  	users = {
		"julian" = import ./home.nix;
	};
};


# --------------------custom options---------------

greetd.enable = true;
sound-module.enable = true;

# --------------------custom options end-----------

  # DO NOT EDIT!!!
  system.stateVersion = "24.05"; # Did you read the comment?

}
