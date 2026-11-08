#!/usr/bin/env python3
"""Offline tests: no Avahi daemon, networking, or writes to the real /etc."""

import ctypes
import fcntl
import importlib.util
import io
import multiprocessing
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
helper = Path(
    os.environ.get(
        "REMOTE_BUILDER_MDNS_HELPER",
        Path(__file__).resolve().parents[1]
        / "modules/nixos/scripts/remote-builder-mdns.py",
    )
)
spec = importlib.util.spec_from_file_location("remote_builder_mdns", helper)
mdns = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mdns)


class HostsFileTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.static = self.root / "static-hosts"
        self.output = self.root / "hosts"
        self.state = self.root / "state"
        self.static.write_text("127.0.0.1 localhost")
        self.hosts = mdns.HostsFile(
            "builder.local", self.static, self.output, self.state
        )

    def assert_locked(self):
        with (self.state / "hosts.lock").open("r+") as lock:
            with self.assertRaises(BlockingIOError):
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def assert_address(self, ip):
        self.assertEqual((self.state / "ip").read_text(), f"{ip}\n")
        self.assertEqual(
            self.output.read_text(),
            f"127.0.0.1 localhost\n{ip} builder.local # remote-builder-mdns\n",
        )

    def test_updates_restore_static_content_and_remove_stale_address(self):
        self.output.symlink_to(self.static)
        self.hosts.sync("192.0.2.1")
        self.assertFalse(self.output.is_symlink())
        self.assert_address("192.0.2.1")
        self.assertEqual(self.static.read_text(), "127.0.0.1 localhost")
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o644)
        self.hosts.sync("192.0.2.2")
        self.assert_address("192.0.2.2")
        lock_inode = (self.state / "hosts.lock").stat().st_ino

        # Simulate setup-etc replacing /etc/hosts on activation.
        self.static.write_text("127.0.0.1 localhost\n::1 localhost\n")
        self.output.write_text(self.static.read_text())
        self.hosts.restore()
        self.assertEqual(
            self.output.read_text(),
            self.static.read_text() + "192.0.2.2 builder.local # remote-builder-mdns\n",
        )
        self.hosts.sync(None)
        self.assertFalse((self.state / "ip").exists())
        self.assertEqual(self.output.read_text(), self.static.read_text())
        self.hosts.restore()
        self.assertEqual((self.state / "hosts.lock").stat().st_ino, lock_inode)

    def test_invalid_address_cannot_overwrite_good_state(self):
        self.hosts.sync("192.0.2.1")
        for ip in ("bad-address", "::1", "192.0.2.2\ninjected"):
            with self.subTest(ip=ip), self.assertRaises(ValueError):
                self.hosts.sync(ip)
            self.assert_address("192.0.2.1")

    def test_unique_same_directory_temporaries_are_cleaned_up(self):
        replace = mdns.os.replace
        paths = []

        def observed(source, destination):
            paths.append(source)
            self.assertEqual(source.parent, destination.parent)
            self.assertEqual(source.stat().st_mode & 0o777, 0o644)
            replace(source, destination)

        with mock.patch.object(mdns.os, "replace", side_effect=observed):
            self.hosts.sync("192.0.2.1")
            self.hosts.sync("192.0.2.2")
        self.assertEqual(len(paths), 4)
        self.assertEqual(len(set(paths)), 4)
        self.assertTrue(all(not path.exists() for path in paths))
        self.assertEqual(list(self.root.rglob("*.remote-builder.*")), [])

    def test_failed_hosts_replace_preserves_recoverable_intent(self):
        replace = mdns.os.replace

        def fail_hosts(source, destination):
            if destination == self.output:
                raise OSError("injected hosts replacement failure")
            replace(source, destination)

        for ip in ("192.0.2.2", None):
            with self.subTest(ip=ip):
                self.hosts.sync("192.0.2.1")
                with mock.patch.object(mdns.os, "replace", side_effect=fail_hosts):
                    with self.assertRaises(OSError):
                        self.hosts.sync(ip)
                self.assertEqual(list(self.root.rglob("*.remote-builder.*")), [])
                self.hosts.restore()
                if ip is None:
                    self.assertEqual(
                        self.output.read_text(), self.static.read_text() + "\n"
                    )
                    self.assertFalse((self.state / "ip").exists())
                else:
                    self.assert_address(ip)

    def test_lock_covers_cached_state_reads_writes_and_hosts_replacement(self):
        read_text = Path.read_text
        unlink = Path.unlink
        replace = mdns.HostsFile._replace
        observed = set()

        def locked_read(path, *args, **kwargs):
            if path == self.state / "ip":
                self.assert_locked()
                observed.add("read")
            return read_text(path, *args, **kwargs)

        def locked_unlink(path, *args, **kwargs):
            if path == self.state / "ip":
                self.assert_locked()
                observed.add("remove")
            return unlink(path, *args, **kwargs)

        def locked_replace(path, text):
            self.assert_locked()
            observed.add("hosts" if path == self.output else "state")
            replace(path, text)

        with (
            mock.patch.object(Path, "read_text", locked_read),
            mock.patch.object(Path, "unlink", locked_unlink),
            mock.patch.object(self.hosts, "_replace", side_effect=locked_replace),
        ):
            self.hosts.sync("192.0.2.1")
            self.hosts.restore()
            self.hosts.sync(None)
            self.hosts.restore()
        self.assertEqual(observed, {"read", "remove", "hosts", "state"})

    def test_restore_cannot_overwrite_a_concurrent_new_update(self):
        self.hosts.sync("192.0.2.1")
        context = multiprocessing.get_context("fork")
        ready, send_ready = context.Pipe(duplex=False)
        release, send_release = context.Pipe(duplex=False)
        started, send_started = context.Pipe(duplex=False)
        for pipe in (ready, send_ready, release, send_release, started, send_started):
            self.addCleanup(pipe.close)

        class PausedRestore(mdns.HostsFile):
            def _write_hosts(inner, ip):
                send_ready.send(ip)
                if not release.poll(15):
                    raise RuntimeError("restore was never released")
                release.recv()
                super()._write_hosts(ip)

        restoring = PausedRestore("builder.local", self.static, self.output, self.state)

        def update():
            send_started.send(True)
            self.hosts.sync("192.0.2.2")

        processes = [
            context.Process(target=restoring.restore),
            context.Process(target=update),
        ]
        try:
            processes[0].start()
            self.assertTrue(ready.poll(15))
            self.assertEqual(ready.recv(), "192.0.2.1")
            # No sleeps/racy success criterion: the old snapshot must still
            # hold the shared lock before a second process starts its update.
            self.assert_locked()
            processes[1].start()
            self.assertTrue(started.poll(15))
            started.recv()
            send_release.send(True)
            for process in processes:
                process.join(15)
                self.assertEqual(process.exitcode, 0)
            self.assert_address("192.0.2.2")
        finally:
            for process in processes:
                if process.is_alive():
                    process.terminate()
                if process.pid is not None:
                    process.join(15)

    def test_prefers_recent_non_link_local_addresses(self):
        records = {(1, "192.0.2.1"): None, (2, "169.254.1.1"): None}
        self.assertEqual(mdns.pick_ip(records), "192.0.2.1")
        records[(3, "192.0.2.2")] = None
        self.assertEqual(mdns.pick_ip(records), "192.0.2.2")
        self.assertEqual(mdns.pick_ip({(2, "169.254.1.1"): None}), "169.254.1.1")
        self.assertIsNone(mdns.pick_ip({}))


class CallbackTests(unittest.TestCase):
    def test_ctypes_callback_exception_reaches_failure_handler(self):
        on_error = mock.Mock()

        @ctypes.CFUNCTYPE(None)
        @mdns.guard_callback(on_error)
        def callback():
            raise OSError("injected callback failure")

        diagnostic = io.StringIO()
        with redirect_stderr(diagnostic):
            callback()
        on_error.assert_called_once_with()
        self.assertIn("injected callback failure", diagnostic.getvalue())
        self.assertNotIn("Exception ignored", diagnostic.getvalue())

    def run_fake_avahi(self, failure):
        common, client, hosts = mock.Mock(), mock.Mock(), mock.Mock()
        common.avahi_simple_poll_new.return_value = 1
        common.avahi_simple_poll_get.return_value = 2
        common.avahi_simple_poll_loop.return_value = -1 if failure == "poll" else 0

        def browser_new(*args):
            if failure == "client":
                raise OSError("injected client callback failure")
            args[-2](
                None,
                1,
                0,
                mdns.AVAHI_BROWSER_ALL_FOR_NOW,
                b"builder.local",
                1,
                1,
                None,
                0,
                0,
                None,
            )
            return 3

        def client_new(_poll, _flags, callback, _data, _error):
            callback(4, mdns.AVAHI_CLIENT_S_RUNNING, None)
            return 4

        client.avahi_client_new.side_effect = client_new
        client.avahi_record_browser_new.side_effect = browser_new
        if failure == "record":
            hosts.sync.side_effect = OSError("injected record callback failure")
        diagnostic = io.StringIO()
        with (
            mock.patch.object(sys, "argv", [str(helper), "--host", "builder.local"]),
            mock.patch.object(mdns, "HostsFile", return_value=hosts),
            mock.patch.object(mdns.ctypes, "CDLL", side_effect=[common, client]),
            mock.patch.object(mdns, "sd_notify_ready"),
            redirect_stderr(diagnostic),
        ):
            self.assertEqual(mdns.main(), 1)
        if failure != "poll":
            common.avahi_simple_poll_quit.assert_called_once_with(1)
            common.avahi_simple_poll_loop.assert_not_called()
            self.assertIn(f"injected {failure} callback failure", diagnostic.getvalue())
        client.avahi_client_free.assert_called_once_with(4)
        common.avahi_simple_poll_free.assert_called_once_with(1)

    def test_both_callback_failures_exit_nonzero_for_systemd_restart(self):
        for failure in ("record", "client"):
            with self.subTest(failure=failure):
                self.run_fake_avahi(failure)

    def test_poll_failure_exits_nonzero(self):
        self.run_fake_avahi("poll")

    def test_activation_restore_does_not_load_avahi(self):
        with (
            mock.patch.object(
                sys, "argv", [str(helper), "--host", "builder.local", "--restore"]
            ),
            mock.patch.object(mdns, "HostsFile") as hosts,
            mock.patch.object(mdns.ctypes, "CDLL") as cdll,
        ):
            self.assertEqual(mdns.main(), 0)
        hosts.return_value.restore.assert_called_once_with()
        cdll.assert_not_called()


if __name__ == "__main__":
    unittest.main()
