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
    ../../modules/nixos/obs-studio.nix
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

  # Setting up networking + dns
  services.resolved.enable = false;

  networking = {
    hostName = "junixos";
    networkmanager.enable = true;
    networkmanager.dns = "none";
    nameservers = [ "127.0.0.1" "::1" ];
  };

  services.dnscrypt-proxy = {
    enable = true;
    settings = {
      listen_addresses = [ "127.0.0.1:53" "[::1]:53" ];
      
      ipv6_servers = true;
      
      require_dnssec = true;

      # SPECIFIC MULLVAD CONFIGURATION
      # 'mullvad-adblock-doh' is the pre-defined name for:
      # https://adblock.dns.mullvad.net/dns-query
      server_names = [ "mullvad-adblock-doh" ];
      
      sources.public-resolvers = {
        urls = [
          "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
          "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
        ];
        cache_file = "/var/lib/dnscrypt-proxy2/public-resolvers.md";
        minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
      };
    };
  };



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
    cliphist
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
    zip
    unzip
    traceroute
    whois
    dig
    qimgv
    bat
    python3
    yt-dlp

    zathura
    
    libreoffice-fresh
    hunspell
    hunspellDicts.de_DE
    hunspellDicts.en_US
    hyphenDicts.de_DE
    hyphenDicts.en_US

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

  services.fstrim.enable = true;

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

  # ADDED THIS BLOCK TO ENABLE THE ARK SERVER
  gaming.arkServer = {
    enable = true;
    user = "julian";
  };

  gaming.factorioServer = {
    enable = true;
    user = "julian";
  };

  # --------------------custom options end-----------

  # DO NOT EDIT!!!
  system.stateVersion = "24.05"; # Did you read the comment?

}
