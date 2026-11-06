{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.system.remoteBuilder;
  targetHost = lib.removeSuffix "." cfg.host;
  useAvahiMdns = lib.hasSuffix ".local" targetHost && !config.services.resolved.enable;
  avahiLibDir = "${lib.getLib pkgs.avahi}/lib";

  # Lix/Nix calls `__nss_configure_lookup("hosts", "files dns")` inside
  # `initLibStore()`, bypassing nscd/nsncd and `/etc/nsswitch.conf` (including
  # `nss-mdns`). Subscribe to Avahi's IPv4 A-record browser over D-Bus so
  # `<host>.local` stays atomically synced in `/etc/hosts` while reachable on
  # the LAN and is removed immediately when offline.
  mdnsHostsSync = pkgs.writeText "remote-builder-mdns-sync.py" ''
    import ctypes
    import os
    import socket
    import sys
    import time
    from pathlib import Path

    TARGET_HOST = ${builtins.toJSON targetHost}
    AVAHI_COMMON_SO = ${builtins.toJSON "${avahiLibDir}/libavahi-common.so.3"}
    AVAHI_CLIENT_SO = ${builtins.toJSON "${avahiLibDir}/libavahi-client.so.3"}

    STATIC_HOSTS = Path("/etc/static/hosts")
    ETC_HOSTS = Path("/etc/hosts")
    STATE_IP = Path("/run/remote-builder/ip")

    AVAHI_IF_UNSPEC = -1
    AVAHI_PROTO_INET = 0
    AVAHI_CLIENT_NO_FAIL = 2
    AVAHI_CLIENT_S_REGISTERING = 1
    AVAHI_CLIENT_S_RUNNING = 2
    AVAHI_CLIENT_S_COLLISION = 3
    AVAHI_CLIENT_FAILURE = 100
    AVAHI_LOOKUP_USE_MULTICAST = 2
    AVAHI_BROWSER_NEW = 0
    AVAHI_BROWSER_REMOVE = 1
    AVAHI_BROWSER_ALL_FOR_NOW = 3
    AVAHI_BROWSER_FAILURE = 4
    AVAHI_DNS_CLASS_IN = 1
    AVAHI_DNS_TYPE_A = 1


    def sd_notify_ready() -> None:
        sock_path = os.environ.get("NOTIFY_SOCKET")
        if not sock_path:
            return
        if sock_path.startswith("@"):
            sock_path = "\0" + sock_path[1:]
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
                sock.sendto(b"READY=1\n", sock_path)
        except OSError as exc:
            print(f"sd_notify failed: {exc}", file=sys.stderr, flush=True)


    def pick_ip(records: dict[tuple[int, str], None]) -> str | None:
        ips = [ip for (_ifindex, ip) in reversed(records)]
        for ip in ips:
            if not ip.startswith("169.254."):
                return ip
        return ips[0] if ips else None


    def sync_hosts(ip: str | None) -> None:
        if ip is not None:
            ip_tmp = STATE_IP.with_name(".ip.tmp")
            ip_tmp.write_text(f"{ip}\n", encoding="utf-8")
            os.replace(ip_tmp, STATE_IP)
        else:
            STATE_IP.unlink(missing_ok=True)

        base = STATIC_HOSTS.read_text(encoding="utf-8")
        if base and not base.endswith("\n"):
            base += "\n"
        desired = f"{base}{ip} {TARGET_HOST} # remote-builder-mdns\n" if ip is not None else base

        if not ETC_HOSTS.is_symlink() and ETC_HOSTS.exists():
            try:
                if ETC_HOSTS.read_text(encoding="utf-8") == desired:
                    return
            except OSError:
                pass

        tmp = ETC_HOSTS.with_name(".hosts.remote-builder.tmp")
        tmp.write_text(desired, encoding="utf-8")
        os.chmod(tmp, 0o644)
        os.replace(tmp, ETC_HOSTS)


    def main() -> int:
        avahi_common = ctypes.CDLL(AVAHI_COMMON_SO, mode=ctypes.RTLD_GLOBAL)
        avahi_client = ctypes.CDLL(AVAHI_CLIENT_SO)

        client_cb_t = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p)
        record_cb_t = ctypes.CFUNCTYPE(
            None,
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint16,
            ctypes.c_uint16,
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.c_int,
            ctypes.c_void_p,
        )

        avahi_common.avahi_simple_poll_new.argtypes = []
        avahi_common.avahi_simple_poll_new.restype = ctypes.c_void_p
        avahi_common.avahi_simple_poll_get.argtypes = [ctypes.c_void_p]
        avahi_common.avahi_simple_poll_get.restype = ctypes.c_void_p
        avahi_common.avahi_simple_poll_iterate.argtypes = [ctypes.c_void_p, ctypes.c_int]
        avahi_common.avahi_simple_poll_iterate.restype = ctypes.c_int
        avahi_common.avahi_simple_poll_loop.argtypes = [ctypes.c_void_p]
        avahi_common.avahi_simple_poll_loop.restype = ctypes.c_int
        avahi_common.avahi_simple_poll_quit.argtypes = [ctypes.c_void_p]
        avahi_common.avahi_simple_poll_quit.restype = None
        avahi_common.avahi_simple_poll_free.argtypes = [ctypes.c_void_p]
        avahi_common.avahi_simple_poll_free.restype = None
        avahi_common.avahi_strerror.argtypes = [ctypes.c_int]
        avahi_common.avahi_strerror.restype = ctypes.c_char_p

        avahi_client.avahi_client_new.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            client_cb_t,
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_int),
        ]
        avahi_client.avahi_client_new.restype = ctypes.c_void_p
        avahi_client.avahi_client_errno.argtypes = [ctypes.c_void_p]
        avahi_client.avahi_client_errno.restype = ctypes.c_int
        avahi_client.avahi_client_free.argtypes = [ctypes.c_void_p]
        avahi_client.avahi_client_free.restype = None
        avahi_client.avahi_record_browser_new.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint16,
            ctypes.c_uint16,
            ctypes.c_int,
            record_cb_t,
            ctypes.c_void_p,
        ]
        avahi_client.avahi_record_browser_new.restype = ctypes.c_void_p

        simple_poll = avahi_common.avahi_simple_poll_new()
        if not simple_poll:
            print("avahi_simple_poll_new failed", file=sys.stderr, flush=True)
            return 1

        poll_api = avahi_common.avahi_simple_poll_get(simple_poll)
        active_records: dict[tuple[int, str], None] = {}
        browser = None
        notified = False
        exit_code = 0

        def mark_ready() -> None:
            nonlocal notified
            if not notified:
                notified = True
                sd_notify_ready()

        @record_cb_t
        def on_record(_b, interface, _proto, event, _name, _clazz, rtype, rdata, size, _flags, _ud):
            nonlocal exit_code
            if event == AVAHI_BROWSER_NEW and rtype == AVAHI_DNS_TYPE_A and size == 4 and rdata:
                ip = socket.inet_ntop(socket.AF_INET, ctypes.string_at(rdata, 4))
                active_records.pop((interface, ip), None)
                active_records[(interface, ip)] = None
                sync_hosts(pick_ip(active_records))
                mark_ready()
            elif event == AVAHI_BROWSER_REMOVE and rtype == AVAHI_DNS_TYPE_A and size == 4 and rdata:
                ip = socket.inet_ntop(socket.AF_INET, ctypes.string_at(rdata, 4))
                active_records.pop((interface, ip), None)
                sync_hosts(pick_ip(active_records))
            elif event == AVAHI_BROWSER_ALL_FOR_NOW:
                sync_hosts(pick_ip(active_records))
                mark_ready()
            elif event == AVAHI_BROWSER_FAILURE:
                exit_code = 1
                avahi_common.avahi_simple_poll_quit(simple_poll)

        @client_cb_t
        def on_client(c, state, _ud):
            nonlocal browser, exit_code
            if state in (
                AVAHI_CLIENT_S_RUNNING,
                AVAHI_CLIENT_S_REGISTERING,
                AVAHI_CLIENT_S_COLLISION,
            ):
                if browser is None:
                    browser = avahi_client.avahi_record_browser_new(
                        c,
                        AVAHI_IF_UNSPEC,
                        AVAHI_PROTO_INET,
                        TARGET_HOST.encode("utf-8"),
                        AVAHI_DNS_CLASS_IN,
                        AVAHI_DNS_TYPE_A,
                        AVAHI_LOOKUP_USE_MULTICAST,
                        on_record,
                        None,
                    )
                    if not browser:
                        err_no = avahi_client.avahi_client_errno(c)
                        err_msg = avahi_common.avahi_strerror(err_no)
                        msg = err_msg.decode("utf-8", "replace") if err_msg else str(err_no)
                        print(f"avahi_record_browser_new failed: {msg}", file=sys.stderr, flush=True)
                        exit_code = 1
                        avahi_common.avahi_simple_poll_quit(simple_poll)
            elif state == AVAHI_CLIENT_FAILURE:
                err_no = avahi_client.avahi_client_errno(c)
                err_msg = avahi_common.avahi_strerror(err_no)
                msg = err_msg.decode("utf-8", "replace") if err_msg else str(err_no)
                print(f"Avahi client disconnected: {msg}", file=sys.stderr, flush=True)
                exit_code = 1
                avahi_common.avahi_simple_poll_quit(simple_poll)

        err = ctypes.c_int(0)
        client = avahi_client.avahi_client_new(
            poll_api,
            AVAHI_CLIENT_NO_FAIL,
            on_client,
            None,
            ctypes.byref(err),
        )
        if not client:
            err_msg = avahi_common.avahi_strerror(err.value)
            msg = err_msg.decode("utf-8", "replace") if err_msg else str(err.value)
            print(f"avahi_client_new failed: {msg}", file=sys.stderr, flush=True)
            avahi_common.avahi_simple_poll_free(simple_poll)
            return 1

        try:
            deadline = time.monotonic() + 2.0
            while not notified and exit_code == 0:
                remaining_ms = int((deadline - time.monotonic()) * 1000)
                if remaining_ms <= 0:
                    mark_ready()
                    break
                rc = avahi_common.avahi_simple_poll_iterate(simple_poll, remaining_ms)
                if rc != 0:
                    if exit_code == 0:
                        exit_code = 1
                    break
            if exit_code == 0:
                mark_ready()
                avahi_common.avahi_simple_poll_loop(simple_poll)
        finally:
            avahi_client.avahi_client_free(client)
            avahi_common.avahi_simple_poll_free(simple_poll)

        return exit_code


    if __name__ == "__main__":
        raise SystemExit(main())
  '';
in
{
  options.custom.system.remoteBuilder = {
    enable = lib.mkEnableOption "offload Nix builds and pull binary substitutions from the LAN build server";

    host = lib.mkOption {
      type = lib.types.str;
      default = "junixsrv.local";
      description = "Hostname or IP address of the remote Nix build server.";
    };

    hostPublicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFltIvsEVPVrWUfmBrEWFWuEeAncm5TdkBBcKL/FAUFz";
      description = "SSH host public key pinned in known_hosts (null falls back to accept-new).";
    };

    cachePublicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "junixsrv-1:hMSOLgD3WfEncRLN8nMULXRzks7yAoIEtqDNNnKkD4g=";
      description = "Public signing key from /var/lib/harmonia/cache-pub-key.pem on the build server.";
    };

    maxJobs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Maximum concurrent build jobs to schedule on the remote server.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.nix_builder_ssh_key = {
      sopsFile = ../../secrets/common.yaml;
      key = "user_ssh_key";
      owner = "root";
      mode = "0400";
    };

    services.avahi = lib.mkIf useAvahiMdns {
      enable = lib.mkDefault true;
      openFirewall = lib.mkDefault true;
    };

    environment.etc = lib.mkIf useAvahiMdns {
      hosts.mode = "0644";
    };

    # `setup-etc.pl` re-copies `/etc/static/hosts` to `/etc/hosts` on every
    # switch; immediately re-apply any cached mDNS IP so `<host>.local` never
    # blips out during `nh os switch`.
    system.activationScripts.remoteBuilderHosts = lib.mkIf useAvahiMdns {
      deps = [ "etc" ];
      text = ''
        if [ -s /run/remote-builder/ip ]; then
          read -r ip < /run/remote-builder/ip || true
          if [ -n "$ip" ]; then
            {
              cat /etc/static/hosts
              printf '%s %s # remote-builder-mdns\n' "$ip" ${lib.escapeShellArg targetHost}
            } > /etc/.hosts.remote-builder.tmp
            chmod 0644 /etc/.hosts.remote-builder.tmp
            mv -f /etc/.hosts.remote-builder.tmp /etc/hosts
          fi
        fi
      '';
    };

    systemd.services = {
      remote-builder-mdns = lib.mkIf useAvahiMdns {
        description = "Sync Avahi mDNS IPv4 record for ${targetHost} into /etc/hosts";
        wantedBy = [ "multi-user.target" ];
        after = [
          "dbus.service"
          "avahi-daemon.service"
        ];
        requires = [ "avahi-daemon.service" ];
        restartTriggers = [ config.environment.etc.hosts.source ];
        serviceConfig = {
          Type = "notify";
          NotifyAccess = "main";
          ExecStart = "${pkgs.python3}/bin/python3 ${mdnsHostsSync}";
          Restart = "always";
          RestartSec = "1s";
          RuntimeDirectory = "remote-builder";
          RuntimeDirectoryPreserve = "yes";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = true;
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
        };
      };

      nix-daemon = lib.mkIf useAvahiMdns {
        after = [ "remote-builder-mdns.service" ];
        wants = [ "remote-builder-mdns.service" ];
      };
    };

    programs.ssh = {
      knownHosts = lib.optionalAttrs (cfg.hostPublicKey != null) {
        ${targetHost}.publicKey = cfg.hostPublicKey;
      };
      # Fail fast when away from the home LAN so laptop builds fall back locally in <=3s,
      # and bypass user gpg-agent hooks when nix-daemon connects as root.
      extraConfig = ''
        Host ${targetHost}
          Port 22
          IdentitiesOnly yes
          IdentityAgent none
          ConnectTimeout 3
          ConnectionAttempts 1
          ServerAliveInterval 15
          ServerAliveCountMax 2
          ${lib.optionalString (cfg.hostPublicKey == null) "StrictHostKeyChecking accept-new"}
      '';
    };

    nix = {
      distributedBuilds = true;

      buildMachines = [
        {
          hostName = targetHost;
          protocol = "ssh-ng";
          sshUser = "nixbuilder";
          sshKey = config.sops.secrets.nix_builder_ssh_key.path;
          systems = [ "x86_64-linux" ];
          inherit (cfg) maxJobs;
          speedFactor = 2;
          supportedFeatures = [
            "benchmark"
            "big-parallel"
          ];
        }
      ];

      settings = {
        builders-use-substitutes = true;
        fallback = true;
        connect-timeout = 3;
        substituters = lib.optionals (cfg.cachePublicKey != null) [
          "http://${targetHost}:5000"
        ];
        trusted-public-keys = lib.optionals (cfg.cachePublicKey != null) [
          cfg.cachePublicKey
        ];
      };
    };
  };
}
