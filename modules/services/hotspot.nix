{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.services.hotspot;
in
{
  options.custom.services.hotspot = {
    enable = lib.mkEnableOption "High-Speed 5GHz Hotspot";

    wifiInterface = lib.mkOption {
      type = lib.types.str;
      description = "The name of the USB Wi-Fi interface (e.g., wlp0s20f0u7).";
    };

    ethernetInterface = lib.mkOption {
      type = lib.types.str;
      description = "The name of the internet source interface (e.g., enp7s0).";
    };

    ssid = lib.mkOption {
      type = lib.types.str;
      default = "6-7";
    };

    password = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Plaintext password (fallback). Prefer passwordFile for declarative secrets.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to file containing hotspot password (e.g. from sops-nix).";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelParams = [ "usbcore.autosuspend=-1" ];
    boot.extraModprobeConfig = ''
      options rtw88_core disable_aspm=y
      options rtw88_pci disable_aspm=y
      options 88x2bu rtw_power_mgnt=0 rtw_dynamic_ps=0
    '';
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    hardware.wirelessRegulatoryDatabase = true;

    systemd.services.hotspot = {
      description = "High-Speed 5GHz Hotspot";

      conflicts = [
        "suspend.target"
        "hibernate.target"
      ];
      wantedBy = [ "sys-subsystem-net-devices-${cfg.wifiInterface}.device" ];
      bindsTo = [ "sys-subsystem-net-devices-${cfg.wifiInterface}.device" ];
      after = [
        "network.target"
        "NetworkManager.service"
        "sys-subsystem-net-devices-${cfg.wifiInterface}.device"
      ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${pkgs.iw}/bin/iw reg set DE";
        ExecStart = pkgs.writeShellScript "start-hotspot" ''
          ${lib.optionalString (cfg.passwordFile != null) ''
            PASS="$(${pkgs.coreutils}/bin/cat "${cfg.passwordFile}")"
          ''}
          ${lib.optionalString (cfg.passwordFile == null && cfg.password != null) ''
            PASS="${cfg.password}"
          ''}
          exec ${pkgs.linux-wifi-hotspot}/bin/create_ap \
            --ieee80211n --ieee80211ac \
            --ht_capab '[HT40+][SHORT-GI-20][SHORT-GI-40]' \
            --vht_capab '[MAX-A-MPDU-LEN-EXP-7][VHT80][SHORT-GI-80][RX-STBC1]' \
            --freq-band 5 -c 36 \
            ${cfg.wifiInterface} ${cfg.ethernetInterface} "${cfg.ssid}" ''${PASS:+"$PASS"}
        '';
        ExecStop = "${pkgs.linux-wifi-hotspot}/bin/create_ap --stop ${cfg.wifiInterface}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    networking.networkmanager.unmanaged = [ "interface-name:${cfg.wifiInterface}" ];
    networking.firewall.trustedInterfaces = [ cfg.wifiInterface ];

    environment.systemPackages = [
      pkgs.linux-wifi-hotspot
      pkgs.iw
    ];
  };
}
