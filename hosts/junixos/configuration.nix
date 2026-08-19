{ inputs, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules
  ];

  # Host identification & Network DNS
  networking = {
    hostName = "junixos";
    networkmanager.dns = "none";
    nameservers = [
      "127.0.0.1"
      "::1"
    ];
  };
  system.stateVersion = "24.05";

  services.resolved.enable = false;

  services.dnscrypt-proxy = {
    enable = true;
    settings = {
      listen_addresses = [
        "127.0.0.1:53"
        "[::1]:53"
      ];

      ipv4_servers = true;
      ipv6_servers = true;
      dnscrypt_servers = true;
      doh_servers = true;

      require_dnssec = true;
      require_nofilter = false;

      bootstrap_resolvers = [
        "9.9.9.9:53"
      ];

      server_names = [
        "quad9-dnscrypt-ip4-filter-pri"
        "quad9-dnscrypt-ip6-filter-pri"
        "quad9-doh-ip4-port443-filter-pri"
        "quad9-doh-ip6-port443-filter-pri"
        "mullvad-base-doh"
        "mullvad-base-doh-ipv6"
      ];

      sources.public-resolvers = {
        urls = [
          "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
          "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
        ];
        cache_file = "/var/lib/dnscrypt-proxy/public-resolvers.md";
        minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
      };
    };
  };

  # Host-specific system packages
  environment.systemPackages = with pkgs; [
    ffmpeg
    gimp
    gparted
    hunspell
    hunspellDicts.de_DE
    hunspellDicts.en_US
    hyphenDicts.de_DE
    hyphenDicts.en_US
    libreoffice-fresh
    tree
  ];

  # Host-specific hardware and daemons
  hardware.amdgpu.opencl.enable = true;
  services.fstrim.enable = true;
  services.openssh = {
    enable = true;
    openFirewall = true;
  };

  home-manager = {
    extraSpecialArgs = { inherit inputs; };
    users = {
      "julian" = import ./home.nix;
    };
  };

  # --------------------custom options---------------

  custom = {
    system = {
      kernel = "cachyos";
      boot.silent.enable = true;
      android.enable = true;
    };

    desktop = {
      hyprland.enable = true;
      greetd.enable = true;
      sound.enable = true;
      obs.enable = true;
      gaming = {
        enable = true;
        arkServer.enable = true;
        factorioServer.enable = true;
      };
    };

    services = {
      hotspot = {
        enable = true;
        wifiInterface = "wlp0s20f0u3";
        ethernetInterface = "enp7s0";
        ssid = "6+7";
        password = "unpure-thoughts-about-ubuntu-and-arch";
      };
      syncthing.enable = true;
      jellyfin.enable = true;
      immich.enable = true;
      meilisearch.enable = true;
      archisteamfarm.enable = true;
      openrgb.enable = true;
      lact.enable = true;
      zapret.enable = true;
      isolatedGaming.enable = true;
      printing.enable = true;
      playerctl.enable = true;
    };
  };

  # --------------------custom options end-----------
}
