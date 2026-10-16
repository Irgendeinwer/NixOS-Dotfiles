{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.gaming.isolated;
  apps = [
    "com.usebottles.bottles"
    "com.valvesoftware.Steam"
  ];
in
{
  options.custom.desktop.gaming.isolated = {
    enable = lib.mkEnableOption "isolated Flatpak gaming environment (Bottles & Sandboxed Steam)";
  };

  config = lib.mkIf cfg.enable {
    services.flatpak.enable = true;

    systemd.tmpfiles.rules = [
      "d /var/lib/flatpak/overrides 0755 root root - -"

      # Override for Bottles: Isolated to ~/UntrustedGames (Read/Write)
      "L+ /var/lib/flatpak/overrides/com.usebottles.bottles - - - - ${pkgs.writeText "bottles-override" ''
        [Context]
        filesystems=!home;!host;~/UntrustedGames:create;
      ''}"

      # Override for Sandboxed Steam: Isolated to ~/UntrustedGames (Read/Write)
      "L+ /var/lib/flatpak/overrides/com.valvesoftware.Steam - - - - ${pkgs.writeText "steam-override" ''
        [Context]
        filesystems=!home;!host;~/UntrustedGames:create;
      ''}"
    ];

    # Install the apps only when they are missing: once present, boot no
    # longer contacts Flathub (or fails without a network).
    systemd.services.flatpak-install = {
      description = "Install the sandboxed Flatpak apps (Bottles, Steam)";
      # Desktop notification on failure (modules/nixos/notify-failure.nix)
      unitConfig.OnFailure = [ "notify-failure@%N.service" ];
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.flatpak ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        missing=()
        for app in ${lib.escapeShellArgs apps}; do
          flatpak info --system "$app" > /dev/null 2>&1 || missing+=("$app")
        done
        if [ ''${#missing[@]} -eq 0 ]; then
          exit 0
        fi
        flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        flatpak install --system -y --noninteractive flathub "''${missing[@]}"
      '';
    };

    # Keep the apps and their runtimes up to date and drop runtimes nothing
    # uses anymore. Persistent: a week missed while the PC was off runs at
    # the next boot.
    systemd.services.flatpak-update = {
      description = "Update Flatpak apps and runtimes";
      # Desktop notification on failure (modules/nixos/notify-failure.nix)
      unitConfig.OnFailure = [ "notify-failure@%N.service" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.flatpak ];
      serviceConfig.Type = "oneshot";
      script = ''
        flatpak update --system -y --noninteractive
        flatpak uninstall --system --unused -y --noninteractive
      '';
    };
    systemd.timers.flatpak-update = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
