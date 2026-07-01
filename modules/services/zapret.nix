{ ... }:

{
  services.zapret = {
    enable = true;
    configureFirewall = false;
    httpSupport = true;
    udpSupport = false;

    params = [
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

          # Block outbound HTTP/3 (QUIC) over UDP for local traffic
          udp dport 443 reject

          # Redirect local HTTP/HTTPS traffic to Zapret
          tcp dport { 80, 443 } queue num 200 bypass
        }

        chain forward {
          type filter hook forward priority 0; policy accept;

          udp dport 443 reject

          tcp dport { 80, 443 } queue num 200 bypass
        }
      '';
    };
  };
}
