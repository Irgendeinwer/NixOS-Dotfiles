{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.services.zapret;
  zapretExclude = pkgs.writeText "zapret-exclude.txt" ''
    ipv64.de
  '';
in
{
  options.custom.services.zapret = {
    enable = lib.mkEnableOption "Zapret DPI bypass service with nftables rules";
  };

  config = lib.mkIf cfg.enable {
    services.zapret = {
      enable = true;
      configureFirewall = false;
      httpSupport = true;
      udpSupport = false;

      params = [
        "--hostlist-exclude=${zapretExclude}"
        "--dpi-desync=fake"
        "--dpi-desync-ttl=2"
      ];
    };

    networking.nftables = {
      enable = true;
      tables.zapret-and-quic = {
        family = "inet";
        content = ''
          chain output {
            type filter hook output priority 0; policy accept;

            # Bypass Zapret for local loopback & private IPv4 / IPv6 subnets
            ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept;
            ip6 daddr { ::1/128, fe80::/10, fd00::/8 } accept;

            # Block outbound HTTP/3 (QUIC) over UDP
            udp dport 443 reject

            # Redirect remaining HTTP/HTTPS traffic to Zapret
            tcp dport { 80, 443 } queue num 200 bypass
          }

          chain forward {
            type filter hook forward priority 0; policy accept;

            ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept;
            ip6 daddr { ::1/128, fe80::/10, fd00::/8 } accept;

            udp dport 443 reject

            tcp dport { 80, 443 } queue num 200 bypass
          }
        '';
      };
    };
  };
}
