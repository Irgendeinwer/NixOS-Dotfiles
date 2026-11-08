import argparse
import ctypes
import fcntl
import functools
import ipaddress
import os
import socket
import sys
import tempfile
import time
import traceback
from contextlib import contextmanager
from pathlib import Path

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


class HostsFile:
    """Serialize mDNS updates and activation restores, including the cached IP."""

    def __init__(
        self,
        host,
        static_hosts=Path("/etc/static/hosts"),
        hosts=Path("/etc/hosts"),
        state_dir=Path("/run/remote-builder"),
    ):
        self.host = host
        self.static_hosts = Path(static_hosts)
        self.hosts = Path(hosts)
        self.state_dir = Path(state_dir)
        self.state_ip = self.state_dir / "ip"

    @contextmanager
    def _locked(self):
        # Activation can run before systemd has created RuntimeDirectory. Keep
        # this directory (and hence the lock inode) across service restarts.
        self.state_dir.mkdir(mode=0o755, parents=True, exist_ok=True)
        fd = os.open(
            self.state_dir / "hosts.lock", os.O_CREAT | os.O_RDWR | os.O_CLOEXEC, 0o600
        )
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            os.close(fd)

    @staticmethod
    def _replace(path, text):
        # Same-directory replacement is atomic. Unique names also prevent
        # collisions with interrupted writers; always clean up failed writes.
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=path.parent,
                prefix=f".{path.name}.remote-builder.",
                delete=False,
            ) as stream:
                temporary = Path(stream.name)
                stream.write(text)
                stream.flush()
                os.fchmod(stream.fileno(), 0o644)
            os.replace(temporary, path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)

    def _write_hosts(self, ip):
        base = self.static_hosts.read_text(encoding="utf-8")
        if base and not base.endswith("\n"):
            base += "\n"
        desired = (
            f"{base}{ip} {self.host} # remote-builder-mdns\n"
            if ip is not None
            else base
        )
        if not self.hosts.is_symlink() and self.hosts.exists():
            if self.hosts.read_text(encoding="utf-8") == desired:
                return
        self._replace(self.hosts, desired)

    def sync(self, ip):
        if ip is not None:
            ip = str(ipaddress.IPv4Address(ip))
        with self._locked():
            if ip is None:
                self.state_ip.unlink(missing_ok=True)
            else:
                self._replace(self.state_ip, f"{ip}\n")
            # Keep the latest intent in state even if replacing /etc/hosts
            # fails. A restart or activation restore can then reconcile it.
            self._write_hosts(ip)

    def restore(self):
        with self._locked():
            try:
                ip = str(
                    ipaddress.IPv4Address(
                        self.state_ip.read_text(encoding="utf-8").strip()
                    )
                )
            except FileNotFoundError:
                ip = None
            self._write_hosts(ip)


def guard_callback(on_error):
    """Never let ctypes swallow a callback exception and leave a stale daemon."""

    def decorate(callback):
        @functools.wraps(callback)
        def guarded(*args):
            try:
                return callback(*args)
            except Exception:
                traceback.print_exc()
                on_error()
                return None

        return guarded

    return decorate


def main() -> int:
    parser = argparse.ArgumentParser(description="Keep one mDNS host in /etc/hosts")
    parser.add_argument("--host", required=True)
    parser.add_argument(
        "--restore", action="store_true", help="Restore cached state during activation"
    )
    parser.add_argument("--avahi-common", default="libavahi-common.so.3")
    parser.add_argument("--avahi-client", default="libavahi-client.so.3")
    args = parser.parse_args()
    hosts = HostsFile(args.host)
    if args.restore:
        hosts.restore()
        return 0

    avahi_common = ctypes.CDLL(args.avahi_common, mode=ctypes.RTLD_GLOBAL)
    avahi_client = ctypes.CDLL(args.avahi_client)

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

    def fail_callback():
        nonlocal exit_code
        exit_code = 1
        avahi_common.avahi_simple_poll_quit(simple_poll)

    @record_cb_t
    @guard_callback(fail_callback)
    def on_record(
        _b, interface, _proto, event, _name, _clazz, rtype, rdata, size, _flags, _ud
    ):
        nonlocal exit_code
        if (
            event == AVAHI_BROWSER_NEW
            and rtype == AVAHI_DNS_TYPE_A
            and size == 4
            and rdata
        ):
            ip = socket.inet_ntop(socket.AF_INET, ctypes.string_at(rdata, 4))
            active_records.pop((interface, ip), None)
            active_records[(interface, ip)] = None
            hosts.sync(pick_ip(active_records))
            mark_ready()
        elif (
            event == AVAHI_BROWSER_REMOVE
            and rtype == AVAHI_DNS_TYPE_A
            and size == 4
            and rdata
        ):
            ip = socket.inet_ntop(socket.AF_INET, ctypes.string_at(rdata, 4))
            active_records.pop((interface, ip), None)
            hosts.sync(pick_ip(active_records))
        elif event == AVAHI_BROWSER_ALL_FOR_NOW:
            hosts.sync(pick_ip(active_records))
            mark_ready()
        elif event == AVAHI_BROWSER_FAILURE:
            exit_code = 1
            avahi_common.avahi_simple_poll_quit(simple_poll)

    @client_cb_t
    @guard_callback(fail_callback)
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
                    args.host.encode("utf-8"),
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
                    print(
                        f"avahi_record_browser_new failed: {msg}",
                        file=sys.stderr,
                        flush=True,
                    )
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
            if avahi_common.avahi_simple_poll_loop(simple_poll) < 0:
                print("Avahi poll loop failed", file=sys.stderr, flush=True)
                exit_code = 1
    finally:
        avahi_client.avahi_client_free(client)
        avahi_common.avahi_simple_poll_free(simple_poll)

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
