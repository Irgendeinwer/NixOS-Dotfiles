{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.custom.user;
in
{
  options.custom.user = lib.mkOption {
    type = lib.types.str;
    default = "julian";
    description = "Primary user account for the system.";
  };

  config = {
    # Boot loader
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.initrd.systemd.enable = true;

    # Networking & Firewall baseline
    networking = {
      networkmanager.enable = true;
      firewall.enable = true;
    };

    # Time and Locale
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

    # Declarative user password from sops
    sops.secrets.user_password = {
      sopsFile = ../../secrets/common.yaml;
      neededForUsers = true;
    };

    # User account configuration
    users.users.${user} = {
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets.user_password.path;
      extraGroups = [
        "networkmanager"
        "wheel"
        "input"
      ];
    };

    # Shell configuration
    users.defaultUserShell = pkgs.zsh;
    environment.shells = with pkgs; [ zsh ];
    programs.zsh.enable = true;

  # Package manager settings
  nixpkgs.config.allowUnfree = true;

  # Core system packages shared across all hosts
  environment.systemPackages = with pkgs; [
    bat
    brightnessctl
    btop
    cliphist
    curl
    dconf
    dig
    dunst
    easyeffects
    inkscape
    kitty
    libnotify
    mako
    obsidian
    pdf4qt
    python3
    qimgv
    ripgrep
    traceroute
    unzip
    wev
    wget
    whois
    wl-clipboard
    yt-dlp
    zathura
    zip
  ];

  # XDG Portals & Polkit
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
  };
  security.polkit.enable = true;

  # System security & diagnostics
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Graphics baseline
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  };
}
