{ inputs, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    inputs.home-manager.nixosModules.home-manager
    ../../modules/nixos/flakes.nix
    ../../modules/nixos/plymouth.nix
    ../../modules/nixos/greetd.nix
    ../../modules/nixos/sound.nix
    ../../modules/nixos/hypr.nix
    ../../modules/nixos/fonts.nix
    ../../modules/nixos/direnv.nix
    ../../modules/nixos/gaming.nix
    ../../modules/nixos/android.nix
    #../../modules/nixos/virt.nix
    ../../modules/nixos/nh.nix

    ../../modules/nixvim/nixvim.nix

    ../../modules/nixos/pkgs.nix

    ../../modules/services/services.nix
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
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
    ];
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    wget
    curl
    kitty
    wofi
    tree
    mako
    ripgrep
    libnotify
    dunst
    wl-clipboard
    # xdg-desktop-portal-gtk
    dconf
    obsidian
    # waybar
    btop
    easyeffects
    gparted
    vlc
    playerctl
    celluloid
    prismlauncher
    zip
    unzip
    traceroute
    whois
    dig
    qimgv
    kdePackages.kdenlive
    kdePackages.kdeconnect-kde
    kdePackages.plasma-integration # For QT theming
    bat
    python3
    yt-dlp
    obs-studio

    zathura
    libreoffice
    inkscape
    gimp
    brightnessctl
    wev
    # swww
    ffmpeg
    gruvbox-gtk-theme
    pdf4qt
  ];

  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [ zsh ];
  programs.zsh.enable = true;

  xdg = {
    portal = {
      enable = true;
      xdgOpenUsePortal = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-hyprland
        # pkgs.xdg-desktop-portal-gtk
      ];
    };
  };

  networking.hosts = {
    "192.168.100.2" = [ "yuno.hadiag.selfhost.bz" ];
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
    extraSpecialArgs = { inherit inputs; };
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
