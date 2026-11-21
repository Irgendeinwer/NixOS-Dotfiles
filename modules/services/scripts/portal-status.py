#!/usr/bin/env python3
"""Read-only JSON status daemon for the junixsrv overview portal.

Exposes `GET /api/status` on loopback only, combining host/cgroup vitals,
allowlisted systemd unit states, and the sanitized `nix-nightly-update` run
summary without accessing private root logs or journals.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import subprocess
import threading
import time
from datetime import UTC, datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

GEN_RE = re.compile(r"system-(\d+)-link$")


def _read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return None


def _parse_int(value: str | None) -> int | None:
    if value is None or value == "" or value == "max":
        return None
    try:
        return int(value)
    except ValueError:
        return None


def read_os_release(path: Path) -> str:
    text = _read_text(path)
    if not text:
        return "NixOS"
    fields: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        fields[key] = val.strip().strip('"').strip("'")
    return fields.get("PRETTY_NAME") or fields.get("NAME") or "NixOS"


def read_generation(profile_link: Path) -> tuple[int | None, str | None]:
    try:
        target = os.readlink(profile_link)
        st = profile_link.lstat()
    except OSError:
        return None, None
    match = GEN_RE.search(target)
    gen = int(match.group(1)) if match else None
    switched_at = datetime.fromtimestamp(st.st_mtime, tz=UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    return gen, switched_at


def read_uptime(proc_root: Path) -> int:
    text = _read_text(proc_root / "uptime")
    if not text:
        return 0
    try:
        return max(0, int(float(text.split()[0])))
    except (ValueError, IndexError):
        return 0


def read_meminfo(proc_root: Path) -> tuple[int | None, int | None]:
    text = _read_text(proc_root / "meminfo")
    if not text:
        return None, None
    values: dict[str, int] = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, rest = line.split(":", 1)
        parts = rest.split()
        if parts:
            try:
                values[key] = int(parts[0]) * 1024
            except ValueError:
                continue
    total = values.get("MemTotal")
    avail = values.get("MemAvailable", values.get("MemFree"))
    if total is None or avail is None:
        return None, None
    return max(0, total - avail), total


def read_memory(proc_root: Path, cgroup_root: Path) -> dict[str, Any]:
    sys_used, sys_total = read_meminfo(proc_root)
    cg_current = _parse_int(_read_text(cgroup_root / "memory.current"))
    cg_max = _parse_int(_read_text(cgroup_root / "memory.max"))
    cg_high = _parse_int(_read_text(cgroup_root / "memory.high"))

    if (
        cg_current is not None
        and cg_max is not None
        and cg_max > 0
        and (sys_total is None or cg_max <= sys_total)
    ):
        pct = round(min(100.0, (cg_current * 100.0) / cg_max), 1)
        return {
            "source": "cgroup",
            "usedBytes": cg_current,
            "totalBytes": cg_max,
            "highBytes": cg_high,
            "percent": pct,
        }

    if sys_used is not None and sys_total is not None and sys_total > 0:
        pct = round(min(100.0, (sys_used * 100.0) / sys_total), 1)
        return {
            "source": "system",
            "usedBytes": sys_used,
            "totalBytes": sys_total,
            "highBytes": None,
            "percent": pct,
        }

    return {
        "source": "unavailable",
        "usedBytes": 0,
        "totalBytes": 0,
        "highBytes": None,
        "percent": 0.0,
    }


def read_disk(disk_path: Path) -> dict[str, Any]:
    target = disk_path if disk_path.exists() else Path("/")
    try:
        st = os.statvfs(target)
    except OSError:
        return {"path": str(target), "usedBytes": 0, "freeBytes": 0, "totalBytes": 0, "percent": 0.0}
    total = st.f_frsize * st.f_blocks
    free = st.f_frsize * st.f_bavail
    used = max(0, total - (st.f_frsize * st.f_bfree))
    pct = round(min(100.0, (used * 100.0) / total), 1) if total > 0 else 0.0
    return {
        "path": str(target),
        "usedBytes": used,
        "freeBytes": free,
        "totalBytes": total,
        "percent": pct,
    }


def _normalize_systemd_timestamp(raw_val: str | None) -> str | None:
    if not raw_val:
        return None
    val = raw_val.strip()
    if val in ("", "n/a", "0", "@0"):
        return None
    if val.startswith("@"):
        try:
            epoch = float(val[1:])
            if epoch > 0:
                return datetime.fromtimestamp(epoch, UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
        except (ValueError, OverflowError, OSError):
            return None
        return None
    return val


def query_systemd_units(
    systemctl_bin: str,
    units: list[str],
    timeout_sec: float = 5.0,
) -> dict[str, dict[str, Any]]:
    if not units:
        return {}
    props = "Id,LoadState,ActiveState,SubState,Result,ActiveEnterTimestamp,NextElapseUSecRealtime"
    cmd = [
        systemctl_bin,
        "show",
        "--no-pager",
        "--timestamp=unix",
        f"--property={props}",
        "--",
        *units,
    ]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout_sec,
        )
    except (OSError, subprocess.SubprocessError):
        return {}
    if proc.returncode != 0 and not proc.stdout:
        return {}

    result: dict[str, dict[str, Any]] = {}
    for block in proc.stdout.strip().split("\n\n"):
        if not block.strip():
            continue
        raw: dict[str, str] = {}
        for line in block.splitlines():
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            raw[k] = v.strip()
        unit_id = raw.get("Id")
        if not unit_id:
            continue
        since = _normalize_systemd_timestamp(raw.get("ActiveEnterTimestamp"))
        next_elapse = _normalize_systemd_timestamp(raw.get("NextElapseUSecRealtime"))
        result[unit_id] = {
            "loadState": raw.get("LoadState", "unknown"),
            "activeState": raw.get("ActiveState", "unknown"),
            "subState": raw.get("SubState", "unknown"),
            "result": raw.get("Result", ""),
            "since": since,
            "nextElapse": next_elapse,
        }
    return result


def read_nightly_summary(path: Path) -> dict[str, Any] | None:
    text = _read_text(path)
    if not text:
        return None
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


class StatusCollector:
    def __init__(self, args: argparse.Namespace) -> None:
        self.hostname: str = args.hostname
        self.nightly_enabled: bool = args.nightly_enabled == "1"
        self.nightly_status_file = Path(args.nightly_status_file)
        self.systemctl_bin: str = args.systemctl
        self.systemctl_timeout: float = max(0.1, args.systemctl_timeout)
        self.proc_root = Path(args.proc_root)
        self.cgroup_root = Path(args.cgroup_root)
        self.os_release = Path(args.os_release)
        self.system_profile = Path(args.system_profile)
        self.disk_path = Path(args.disk_path)
        self.cache_ttl: float = max(0.0, args.cache_ttl)

        dedup_units: list[str] = []
        seen: set[str] = set()
        raw_units = list(args.unit or [])
        if self.nightly_enabled:
            raw_units.extend(["nix-nightly-update.service", "nix-nightly-update.timer"])
        for unit in raw_units:
            if unit and unit not in seen:
                seen.add(unit)
                dedup_units.append(unit)
        self.units = dedup_units

        self._lock = threading.Lock()
        self._cached_at = 0.0
        self._cached_payload: bytes = b"{}"

    def snapshot_bytes(self) -> bytes:
        with self._lock:
            now_mono = time.monotonic()
            if (
                self.cache_ttl > 0
                and self._cached_payload != b"{}"
                and (now_mono - self._cached_at) < self.cache_ttl
            ):
                return self._cached_payload
            payload = json.dumps(self._collect(), separators=(",", ":")).encode("utf-8")
            self._cached_payload = payload
            self._cached_at = time.monotonic()
            return payload

    def _collect(self) -> dict[str, Any]:
        gen, gen_switched_at = read_generation(self.system_profile)
        try:
            load1, load5, load15 = os.getloadavg()
            load_avg = [round(load1, 2), round(load5, 2), round(load15, 2)]
        except OSError:
            load_avg = [0.0, 0.0, 0.0]

        units_map = query_systemd_units(self.systemctl_bin, self.units, self.systemctl_timeout)
        nightly_svc = units_map.get("nix-nightly-update.service", {})
        nightly_timer = units_map.get("nix-nightly-update.timer", {})
        nightly_running = nightly_svc.get("activeState") in ("activating", "active")

        return {
            "timestamp": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "host": {
                "hostname": self.hostname,
                "kernel": os.uname().release,
                "osName": read_os_release(self.os_release),
                "generation": gen,
                "generationSwitchedAt": gen_switched_at,
                "uptimeSeconds": read_uptime(self.proc_root),
                "cpuCount": os.cpu_count() or 1,
                "loadAvg": load_avg,
            },
            "memory": read_memory(self.proc_root, self.cgroup_root),
            "disk": read_disk(self.disk_path),
            "units": units_map,
            "nightly": {
                "enabled": self.nightly_enabled,
                "running": nightly_running,
                "nextRun": nightly_timer.get("nextElapse"),
                "lastRun": read_nightly_summary(self.nightly_status_file)
                if self.nightly_enabled
                else None,
            },
        }


class DaemonThreadingHTTPServer(ThreadingHTTPServer):
    daemon_threads = True


def make_handler(collector: StatusCollector) -> type[BaseHTTPRequestHandler]:
    class PortalStatusHandler(BaseHTTPRequestHandler):
        server_version = "junix-portal-status/1.0"
        timeout = 5

        def log_message(self, format: str, *args: object) -> None:
            return

        def _send_json(self, status: HTTPStatus, body: bytes, head_only: bool = False) -> None:
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if not head_only:
                self.wfile.write(body)

        def _handle_read(self, head_only: bool) -> None:
            path = self.path.split("?", 1)[0]
            if path != "/api/status":
                self._send_json(
                    HTTPStatus.NOT_FOUND,
                    b'{"error":"not_found"}',
                    head_only=head_only,
                )
                return
            self._send_json(
                HTTPStatus.OK,
                collector.snapshot_bytes(),
                head_only=head_only,
            )

        def do_GET(self) -> None:
            self._handle_read(head_only=False)

        def do_HEAD(self) -> None:
            self._handle_read(head_only=True)

        def do_POST(self) -> None:
            self._reject_method()

        def do_PUT(self) -> None:
            self._reject_method()

        def do_DELETE(self) -> None:
            self._reject_method()

        def _reject_method(self) -> None:
            body = b'{"error":"method_not_allowed"}'
            self.send_response(HTTPStatus.METHOD_NOT_ALLOWED)
            self.send_header("Allow", "GET, HEAD")
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return PortalStatusHandler


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="junixsrv portal status daemon")
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--ready-file", default="")
    parser.add_argument("--hostname", default=socket.gethostname())
    parser.add_argument("--nightly-enabled", choices=["0", "1"], default="0")
    parser.add_argument("--nightly-status-file", default="/var/lib/nix-nightly-status/status.json")
    parser.add_argument("--systemctl", default="systemctl")
    parser.add_argument("--systemctl-timeout", type=float, default=5.0)
    parser.add_argument("--proc-root", default="/proc")
    parser.add_argument("--cgroup-root", default="/sys/fs/cgroup")
    parser.add_argument("--os-release", default="/etc/os-release")
    parser.add_argument("--system-profile", default="/nix/var/nix/profiles/system")
    parser.add_argument("--disk-path", default="/nix/store")
    parser.add_argument("--cache-ttl", type=float, default=2.0)
    parser.add_argument("--unit", action="append", default=[])
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    collector = StatusCollector(args)
    server = DaemonThreadingHTTPServer((args.bind, args.port), make_handler(collector))
    if args.ready_file:
        bound_host, bound_port = server.server_address[:2]
        Path(args.ready_file).write_text(f"{bound_host}:{bound_port}\n", encoding="utf-8")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
