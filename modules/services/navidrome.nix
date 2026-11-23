{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.navidrome;
  portalEnabled = config.custom.services.portal.enable or false;
  musicOwner = config.custom.services.syncthing.user or config.custom.user;
  musicUnderHome = cfg.musicFolder == "/home" || lib.hasPrefix "/home/" cfg.musicFolder;
  underSyncUserHome = lib.hasPrefix "/home/${musicOwner}/" cfg.musicFolder;
  formatBindHost =
    h: if lib.hasInfix ":" h && !lib.hasPrefix "[" h && !lib.hasPrefix "unix:" h then "[${h}]" else h;
in
{
  options.custom.services.navidrome = {
    enable = lib.mkEnableOption "Navidrome music server";

    reverseProxy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = portalEnabled;
        defaultText = lib.literalExpression "config.custom.services.portal.enable or false";
        description = ''
          Bind Navidrome to loopback (`127.0.0.1`) and expose it over HTTPS via
          the portal's Nginx reverse proxy (`https://<subdomain>.<domainSuffix>`)
          instead of opening raw TCP port 4533 on the network.
        '';
      };

      subdomain = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "music";
        description = "Subdomain prefix under `custom.services.portal.domainSuffix` for the Navidrome virtual host.";
      };

      mobileSubsonicPath = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Also proxy `/music/rest/` and `/music/share/` on the default portal
          vhost so mobile Subsonic clients (e.g. Symfonium over a raw Tailscale
          IP without `/etc/hosts`) can connect to `https://<ip>/music`.
        '';
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = !cfg.reverseProxy.enable;
      defaultText = lib.literalExpression "!config.custom.services.navidrome.reverseProxy.enable";
      description = "Open the Navidrome HTTP port in the firewall.";
    };

    host = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = if cfg.reverseProxy.enable then "127.0.0.1" else "0.0.0.0";
      defaultText = lib.literalExpression ''if reverseProxy.enable then "127.0.0.1" else "0.0.0.0"'';
      description = "Address for Navidrome to listen on.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4533;
      description = "TCP port for Navidrome.";
    };

    musicFolder = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "/home/${config.custom.user}/music";
      defaultText = lib.literalExpression ''"/home/''${config.custom.user}/music"'';
      description = "Absolute path to the music library directory served by Navidrome.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "/" cfg.musicFolder;
        message = "custom.services.navidrome.musicFolder: must be an absolute path.";
      }
    ];

    services.navidrome = {
      enable = true;
      openFirewall = cfg.openFirewall;
      settings = {
        Address = formatBindHost cfg.host;
        Port = cfg.port;
        MusicFolder = cfg.musicFolder;
        Scanner.PurgeMissing = lib.mkDefault "always";
      };
    };

    # Allow Navidrome to read group-accessible Syncthing files inside its
    # chroot without loosening /home/<user> permissions on the host.
    users.users.navidrome = lib.mkIf (config.services.navidrome.user == "navidrome") {
      extraGroups = [ "users" ];
    };

    # Prevent upstream tmpfiles (:700 navidrome:navidrome) from claiming the
    # shared Syncthing folder before Syncthing creates it on first boot.
    systemd.tmpfiles.settings.navidromeDirs.${cfg.musicFolder}."d" = lib.mkIf underSyncUserHome (
      lib.mkForce {
        mode = ":0750";
        user = ":${musicOwner}";
        group = ":users";
      }
    );

    systemd.services.navidrome = {
      after = lib.optionals config.services.syncthing.enable [ "syncthing.service" ];
      serviceConfig = lib.mkMerge [
        (lib.mkIf config.boot.isContainer {
          PrivateUsers = lib.mkForce false;
        })
        # Upstream sets ProtectHome = true, which mounts /home inaccessible even
        # inside RootDirectory = /run/navidrome. Mount an empty read-only tmpfs
        # on /home instead so BindReadOnlyPaths exposes only musicFolder.
        (lib.mkIf musicUnderHome {
          ProtectHome = lib.mkForce "tmpfs";
        })
      ];
    };
  };
}
