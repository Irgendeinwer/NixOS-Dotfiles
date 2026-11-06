{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.custom.user;
  isContainer = config.boot.isContainer;
  hasDesktop = config.custom.desktop.hyprland.enable;
in
{
  options.custom.user = lib.mkOption {
    type = lib.types.str;
    default = "julian";
    description = "Primary user account for the system.";
  };

  config = {
    # Boot loader (containers boot via /sbin/init instead of UEFI)
    boot.loader.systemd-boot.enable = lib.mkIf (!isContainer) true;
    boot.loader.efi.canTouchEfiVariables = lib.mkIf (!isContainer) true;

    # Networking & Firewall baseline
    networking = {
      networkmanager.enable = lib.mkIf (!isContainer) true;
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
        "wheel"
      ]
      ++ lib.optionals (!isContainer) [
        "networkmanager"
      ];
    };

    # Shell configuration
    users.defaultUserShell = pkgs.zsh;
    environment.shells = with pkgs; [ zsh ];
    programs.zsh.enable = true;

    # Package manager settings
    nixpkgs.config.allowUnfree = true;
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    # Hard-link identical files in the store once a week (catches up after
    # downtime); garbage collection stays with nh.
    nix.optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };

    # Core system packages shared across all hosts (GUI utilities only on desktops)
    environment.systemPackages = [
      pkgs.bat
      pkgs.curl
      pkgs.dig
      pkgs.kitty.terminfo
      pkgs.python3
      pkgs.ripgrep
      pkgs.traceroute
      pkgs.unzip
      pkgs.wget
      pkgs.whois
      pkgs.yt-dlp
      pkgs.zip
    ]
    ++ lib.optionals hasDesktop [
      pkgs.brightnessctl
      pkgs.cliphist
      pkgs.dconf
      pkgs.inkscape
      pkgs.libnotify
      pkgs.obsidian
      pkgs.pdf4qt
      pkgs.playerctl
      pkgs.qimgv
      pkgs.wev
      pkgs.wl-clipboard
    ];

    # XDG Portals & Polkit
    xdg.portal = lib.mkIf hasDesktop {
      enable = true;
      xdgOpenUsePortal = true;
    };
    security.polkit.enable = lib.mkIf (!isContainer) true;

    # System security & diagnostics
    programs.mtr.enable = true;
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };

    # Graphics baseline (skip Mesa/32-bit drivers on headless server containers)
    hardware.graphics = lib.mkIf hasDesktop {
      enable = true;
      enable32Bit = true;
    };
  };
}
