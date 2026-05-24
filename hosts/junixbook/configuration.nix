{ inputs, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    inputs.home-manager.nixosModules.home-manager
    ../../modules/nixos/flakes.nix
    ../../modules/nixos/kernel.nix
    ../../modules/nixos/plymouth.nix
    ../../modules/nixos/greetd.nix
    ../../modules/nixos/sound.nix
    ../../modules/nixos/hypr.nix
    ../../modules/nixos/fonts.nix
    ../../modules/nixos/direnv.nix
    ../../modules/nixos/gaming.nix
    ../../modules/nixos/direnv.nix
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/android.nix
    ../../modules/nixos/nh.nix
    ../../modules/nixos/obs-studio.nix

    ../../modules/nixvim/nixvim.nix

    ../../modules/nixos/pkgs.nix

    ../../modules/services/syncthing.nix
    ../../modules/services/printing.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.systemd.enable = true;

  networking.hostName = "junixbook";

  networking.networkmanager.enable = true;

  environment.etc."ssl/certs/iserv.pem".source = ../../assets/iserv.pem;

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
    scrcpy
    wget
    curl
    kitty
    ripgrep
    mako
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
    zip
    unzip
    traceroute
    whois
    dig
    qimgv
    bat
    # anki
    python3
    yt-dlp
    zathura
    pdf4qt
    libreoffice
    inkscape
    brightnessctl
    wev
    networkmanagerapplet
    # swww
    gruvbox-gtk-theme
  ];

  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [ zsh ];
  programs.zsh.enable = true;

  xdg = {
    portal = {
      enable = true;
      xdgOpenUsePortal = true;
      extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
    };
  };

  services.logind.settings.Login.HandlePowerKey = "ignore";

  services.upower.enable = true;

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

  networking.firewall.enable = false;

  home-manager = {
    extraSpecialArgs = { inherit inputs; };
    users = {
      "julian" = import ./home.nix;
    };
  };

  # --------------------custom options---------------

  kernel = "latest";

  greetd.enable = true;
  sound-module.enable = true;

  # --------------------custom options end-----------

  # DO NOT EDIT!!!
  system.stateVersion = "24.05"; # Did you read the comment?

}
