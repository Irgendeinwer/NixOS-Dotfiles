#!/usr/bin/env python3
"""Runtime unit tests for `modules/services/scripts/portal-status.py`."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path


def http_request(url: str, method: str = "GET") -> tuple[int, dict[str, str], bytes]:
    req = urllib.request.Request(url, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            headers = {k.lower(): v for k, v in resp.headers.items()}
            return resp.status, headers, resp.read()
    except urllib.error.HTTPError as err:
        headers = {k.lower(): v for k, v in err.headers.items()}
        return err.code, headers, err.read()


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    helper = Path(
        os.environ.get(
            "PORTAL_STATUS_HELPER",
            str(repo_root / "modules/services/scripts/portal-status.py"),
        )
    )

    with tempfile.TemporaryDirectory() as raw_tmp:
        tmp = Path(raw_tmp)

        proc_dir = tmp / "proc"
        proc_dir.mkdir()
        (proc_dir / "uptime").write_text("90061.42 180000.00\n", encoding="utf-8")
        (proc_dir / "meminfo").write_text(
            "MemTotal:       33554432 kB\nMemAvailable:   25165824 kB\n",
            encoding="utf-8",
        )

        cgroup_dir = tmp / "cgroup"
        cgroup_dir.mkdir()
        (cgroup_dir / "memory.current").write_text(str(3 * 1024**3) + "\n", encoding="utf-8")
        (cgroup_dir / "memory.high").write_text(str(10 * 1024**3) + "\n", encoding="utf-8")
        (cgroup_dir / "memory.max").write_text(str(12 * 1024**3) + "\n", encoding="utf-8")

        os_release = tmp / "os-release"
        os_release.write_text('PRETTY_NAME="NixOS 26.11 (Yarara)"\n', encoding="utf-8")

        profiles = tmp / "profiles"
        profiles.mkdir()
        gen_target = profiles / "system-42-link"
        gen_target.mkdir()
        sys_link = profiles / "system"
        sys_link.symlink_to("system-42-link")

        systemctl_stub = tmp / "systemctl"
        systemctl_stub.write_text(
            "#!/bin/sh\n"
            "cat <<'EOF'\n"
            "Id=navidrome.service\n"
            "LoadState=loaded\n"
            "ActiveState=active\n"
            "SubState=running\n"
            "Result=success\n"
            "ActiveEnterTimestamp=Sat 2026-11-21 02:18:00 CET\n"
            "NextElapseUSecRealtime=n/a\n"
            "\n"
            "Id=syncthing.service\n"
            "LoadState=loaded\n"
            "ActiveState=active\n"
            "SubState=running\n"
            "Result=success\n"
            "ActiveEnterTimestamp=Sat 2026-11-21 02:18:01 CET\n"
            "NextElapseUSecRealtime=\n"
            "\n"
            "Id=nix-nightly-update.service\n"
            "LoadState=loaded\n"
            "ActiveState=inactive\n"
            "SubState=dead\n"
            "Result=success\n"
            "ActiveEnterTimestamp=Sat 2026-11-21 02:29:10 CET\n"
            "NextElapseUSecRealtime=\n"
            "\n"
            "Id=nix-nightly-update.timer\n"
            "LoadState=loaded\n"
            "ActiveState=active\n"
            "SubState=waiting\n"
            "Result=success\n"
            "ActiveEnterTimestamp=Sat 2026-11-21 01:00:00 CET\n"
            "NextElapseUSecRealtime=Sun 2026-11-22 02:15:00 CET\n"
            "EOF\n",
            encoding="utf-8",
        )
        systemctl_stub.chmod(0o755)

        nightly_file = tmp / "status.json"
        nightly_file.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "host": "junixsrv",
                    "state": "success",
                    "stage": "done",
                    "exitCode": 0,
                    "lockUpdated": True,
                    "activationDeferred": False,
                    "finishedAt": "2026-11-21T01:29:10Z",
                    "durationSeconds": 670,
                    "durationHuman": "11m 10s",
                    "hosts": ["junixsrv", "junixbook", "junixos"],
                    "summary": ["flake.lock: updated", "duration: 11m 10s"],
                }
            ),
            encoding="utf-8",
        )

        ready_file = tmp / "ready"
        proc = subprocess.Popen(
            [
                sys.executable,
                "-B",
                str(helper),
                "--bind",
                "127.0.0.1",
                "--port",
                "0",
                "--ready-file",
                str(ready_file),
                "--hostname",
                "junixsrv",
                "--nightly-enabled",
                "1",
                "--nightly-status-file",
                str(nightly_file),
                "--systemctl",
                str(systemctl_stub),
                "--proc-root",
                str(proc_dir),
                "--cgroup-root",
                str(cgroup_dir),
                "--os-release",
                str(os_release),
                "--system-profile",
                str(sys_link),
                "--disk-path",
                str(tmp),
                "--cache-ttl",
                "0",
                "--unit",
                "navidrome.service",
                "--unit",
                "syncthing.service",
            ]
        )
        try:
            deadline = time.monotonic() + 5.0
            while not ready_file.exists():
                if proc.poll() is not None:
                    raise RuntimeError(f"daemon exited early: {proc.returncode}")
                if time.monotonic() > deadline:
                    raise TimeoutError("timed out waiting for portal-status daemon")
                time.sleep(0.02)

            addr = ready_file.read_text(encoding="utf-8").strip()
            base_url = f"http://{addr}"

            code, headers, body = http_request(f"{base_url}/api/status")
            assert code == 200, code
            assert "application/json" in headers["content-type"]
            assert headers["cache-control"] == "no-store"
            payload = json.loads(body.decode("utf-8"))

            assert payload["host"]["hostname"] == "junixsrv"
            assert payload["host"]["osName"] == "NixOS 26.11 (Yarara)"
            assert payload["host"]["generation"] == 42
            assert payload["host"]["uptimeSeconds"] == 90061

            assert payload["memory"]["source"] == "cgroup"
            assert payload["memory"]["usedBytes"] == 3 * 1024**3
            assert payload["memory"]["totalBytes"] == 12 * 1024**3
            assert payload["memory"]["percent"] == 25.0

            assert payload["disk"]["totalBytes"] > 0
            assert payload["units"]["navidrome.service"]["activeState"] == "active"
            assert payload["units"]["navidrome.service"]["subState"] == "running"
            assert payload["units"]["syncthing.service"]["since"] is not None

            assert payload["nightly"]["enabled"] is True
            assert payload["nightly"]["running"] is False
            assert payload["nightly"]["nextRun"] == "Sun 2026-11-22 02:15:00 CET"
            assert payload["nightly"]["lastRun"]["state"] == "success"

            # Verify fallback to /proc/meminfo when cgroup memory.max is "max"
            (cgroup_dir / "memory.max").write_text("max\n", encoding="utf-8")
            code2, _, body2 = http_request(f"{base_url}/api/status")
            assert code2 == 200
            payload2 = json.loads(body2.decode("utf-8"))
            assert payload2["memory"]["source"] == "system"
            assert payload2["memory"]["percent"] == 25.0

            # HEAD returns empty body with matching content-length
            head_code, head_headers, head_body = http_request(f"{base_url}/api/status", "HEAD")
            assert head_code == 200
            assert head_body == b""
            assert int(head_headers["content-length"]) > 100

            # Unknown path -> 404, mutating method -> 405
            not_found, _, _ = http_request(f"{base_url}/other")
            assert not_found == 404
            not_allowed, allow_headers, _ = http_request(f"{base_url}/api/status", "POST")
            assert not_allowed == 405
            assert allow_headers.get("allow") == "GET, HEAD"
        finally:
            proc.terminate()
            proc.wait(timeout=5)

    print("portal-status tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
