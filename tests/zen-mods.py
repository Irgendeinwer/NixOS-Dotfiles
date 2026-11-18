#!/usr/bin/env python3
"""Isolated tests for Zen Mod adoption; never touches a real browser profile."""

import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HELPER = Path(os.environ["ZEN_MODS_HELPER"])
spec = importlib.util.spec_from_file_location("zen_mods", HELPER)
zen = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = zen
spec.loader.exec_module(zen)

A = "58649066-2b6f-4a5b-af6d-c3d21d16fc00"
B = "d8b79d4a-6cba-4495-9ff6-d6d30b0e94fe"
EXTRA = "12345678-1234-1234-1234-123456789abc"
DISABLED = "12345678-1234-1234-1234-123456789abd"
LEFTOVER = "1e86cf37-a127-4f24-b919-d265b5ce29a0"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def tree(root):
    """Snapshot names, types and file bytes without following symlinks."""
    result = {}
    for path in sorted(root.rglob("*")):
        name = str(path.relative_to(root))
        if path.is_symlink():
            result[name] = ("link", os.readlink(path))
        elif path.is_dir():
            result[name] = ("dir",)
        else:
            result[name] = ("file", path.read_bytes())
    return result


class ZenModsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="zen test ")
        self.base = Path(self.temp.name)
        self.profile = self.base / "home with spaces" / ".zen" / "existing.default"
        self.profile.mkdir(parents=True)
        self.profile_registry = self.profile.parent / "profiles.ini"
        self.profile_registry.write_text(
            f"[Profile0]\nName=default\nIsRelative=1\nPath={self.profile.name}\n",
            encoding="utf-8",
        )
        self.backups = self.base / "state with spaces" / "zen-mod-backups"
        self.sources = self.base / "sources"
        self.sources.mkdir()
        self.manifest_path = self.base / "manifest.json"
        self.a_css = b"/* A pinned */\n.a { color: red; }\n"
        self.a_old = b"/* explicitly approved old A */\n"
        self.a_prefs = (
            b'[{"type":"checkbox","property":"a.enabled","defaultValue":true}]\n'
        )
        self.b_css = b"/* B pinned */\n.b { color: blue; }\n"
        self.write_source("a.css", self.a_css)
        self.write_source("a.json", self.a_prefs)
        self.write_source("b.css", self.b_css)
        self.manifest = [
            {
                "entry": {
                    "id": A,
                    "name": "A",
                    "description": "First",
                    "author": "Author A",
                    "version": "1.0",
                    "preferences": "https://example.invalid/a.json",
                    "enabled": True,
                },
                "files": {
                    "chrome.css": self.file("a.css", self.a_css, [sha(self.a_old)]),
                    "preferences.json": self.file("a.json", self.a_prefs),
                },
            },
            {
                "entry": {
                    "id": B,
                    "name": "B",
                    "description": "Second",
                    "author": "Author B",
                    "version": "1.0",
                    "enabled": True,
                },
                "files": {"chrome.css": self.file("b.css", self.b_css)},
            },
        ]
        self.save_manifest()

    def tearDown(self):
        self.temp.cleanup()

    def write_source(self, name, data):
        (self.sources / name).write_bytes(data)

    def file(self, name, data, previous=None):
        item = {"source": str(self.sources / name), "sha256": sha(data)}
        if previous:
            item["acceptedPreviousSha256"] = previous
        return item

    def save_manifest(self):
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")

    def call(self, mode, *, ok=True):
        result = subprocess.run(
            [
                sys.executable,
                "-B",
                str(HELPER),
                mode,
                "--profile",
                str(self.profile),
                "--registry",
                str(self.profile_registry),
                "--manifest",
                str(self.manifest_path),
                "--backup-root",
                str(self.backups),
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def mod_file(self, mod_id, name, data):
        path = self.profile / "chrome" / "zen-themes" / mod_id / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def registry(self, value):
        path = self.profile / "zen-themes.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_profile_registry_requires_a_registered_profile(self):
        original = self.profile_registry.read_bytes()
        self.profile.with_name("other.default").mkdir()
        # An install section alone is not a profile entry. The relative and
        # absolute flags must also agree with the form of the registered path.
        for contents in (
            b"[Profile0]\nName=other\nIsRelative=1\nPath=other.default\n",
            f"[Install123]\nDefault={self.profile.name}\n".encode(),
            f"[Profile0]\nName=default\nIsRelative=0\nPath={self.profile.name}\n".encode(),
            b"[DEFAULT]\nName=default\nIsRelative=1\nPath=existing.default\n[Profile0]\n",
            original.replace(b"[Profile0]", b"[Profile1]"),
            original.replace(b"Path=", b"Path ="),
            original.replace(b".default\n", b".default \n"),
        ):
            with self.subTest(registry=contents):
                self.profile_registry.write_bytes(contents)
                for mode in ("check", "apply"):
                    result = self.call(mode, ok=False)
                    self.assertIn("is not registered", result.stderr)
                    self.assertEqual(tree(self.profile), {})
                    self.assertEqual(self.profile_registry.read_bytes(), contents)
                    self.assertFalse(self.backups.exists())
        self.profile_registry.write_bytes(b"not an INI file")
        self.assertIn("invalid Zen profile registry", self.call("check", ok=False).stderr)
        self.profile_registry.unlink()
        self.assertIn("profile registry is missing", self.call("apply", ok=False).stderr)
        linked_registry = self.base / "prior-home-manager-files" / "profiles.ini"
        linked_registry.parent.mkdir()
        linked_registry.write_bytes(original)
        self.profile_registry.symlink_to(linked_registry)
        self.assertIn("not a symlink", self.call("apply", ok=False).stderr)
        self.assertEqual(linked_registry.read_bytes(), original)
        self.assertEqual(tree(self.profile), {})
        self.profile_registry.unlink()
        # Keep install entries and other profiles byte-for-byte, including an
        # older registered directory that is no longer on disk.
        registered = (
            "[Profile0]\nName=old\nIsRelative=1\nPath=old.default\n\n"
            f"[Profile1]\nName=default\nIsRelative=0\nPath={self.profile}\n\n"
            f"[Install123]\nDefault={self.profile}\nLocked=1\n"
        ).encode()
        self.profile_registry.write_bytes(registered)
        self.call("apply")
        self.assertTrue((self.profile / "zen-themes.json").is_file())
        self.assertEqual(self.profile_registry.read_bytes(), registered)

    def test_relative_registry_path_preserves_whitespace_and_handles_crlf(self):
        renamed = self.profile.with_name("a recovered profile with trailing space ")
        self.profile.rename(renamed)
        self.profile = renamed
        registry = (
            f"[Profile0]\r\nName=default\r\nIsRelative=1\r\nPath={renamed.name}\r\n"
        ).encode("utf-8-sig")
        self.profile_registry.write_bytes(registry)
        self.call("check")
        self.call("apply")
        self.assertTrue((renamed / "zen-themes.json").is_file())
        self.assertEqual(self.profile_registry.read_bytes(), registry)

    def test_empty_profile_check_is_read_only_and_apply_is_idempotent(self):
        (self.profile / "prefs.js").write_text("personal prefs", encoding="utf-8")
        extensions = self.profile / "extensions"
        extensions.mkdir()
        (extensions / "local.xpi").write_bytes(b"local extension")
        leftover = self.mod_file(LEFTOVER, "chrome.css", b"ignored leftover")
        before = tree(self.profile)
        self.call("check")
        self.assertEqual(tree(self.profile), before)
        self.assertFalse((self.profile / ".parentlock").exists())

        self.call("apply")
        registry = json.loads((self.profile / "zen-themes.json").read_text())
        self.assertEqual(list(registry), [A, B])
        self.assertTrue(registry[A]["enabled"] and registry[B]["enabled"])
        self.assertEqual(
            (self.profile / "chrome" / "zen-themes" / A / "chrome.css").read_bytes(),
            self.a_css,
        )
        self.assertEqual(
            (
                self.profile / "chrome" / "zen-themes" / A / "preferences.json"
            ).read_bytes(),
            self.a_prefs,
        )
        css_path = self.profile / "chrome" / "zen-themes.css"
        css = css_path.read_bytes()
        self.assertLess(css.index(self.a_css), css.index(self.b_css))
        self.assertEqual(leftover.read_bytes(), b"ignored leftover")
        self.assertEqual((self.profile / "prefs.js").read_text(), "personal prefs")
        self.assertEqual((extensions / "local.xpi").read_bytes(), b"local extension")
        self.assertFalse(self.backups.exists())

        # Zen's generated timestamp alone must not create a new backup/rewrite.
        css_path.write_bytes(
            css.replace(b"NixOS-Dotfiles reconciliation", b"some browser timestamp")
        )
        after = tree(self.profile)
        result = self.call("apply")
        self.assertIn("already reconciled", result.stdout)
        self.assertEqual(tree(self.profile), after)
        self.assertFalse(self.backups.exists())

    def test_existing_state_is_merged_and_replaced_files_are_backed_up(self):
        old_css = self.mod_file(A, "chrome.css", self.a_old)
        self.mod_file(A, "preferences.json", self.a_prefs)
        extra_css = b"/* user extra */\n.extra { display: none; }\n"
        self.mod_file(EXTRA, "chrome.css", extra_css)
        self.mod_file(DISABLED, "chrome.css", b"/* disabled extra */")
        self.mod_file(LEFTOVER, "notes.txt", b"do not touch")
        registry = {
            EXTRA: {
                "id": EXTRA,
                "name": "Extra",
                "author": "Other",
                "description": "Kept",
                "enabled": True,
            },
            A: {
                "id": A,
                "name": "old name",
                "enabled": True,
                "customProperty": {"keep": 1},
            },
            DISABLED: {"id": DISABLED, "name": "Disabled", "enabled": False},
        }
        registry_path = self.registry(registry)
        original_registry = registry_path.read_bytes()
        original_mode = registry_path.stat().st_mode & 0o777
        aggregate = self.profile / "chrome" / "zen-themes.css"
        # Match the pinned Zen browser's wire format independently of our
        # renderer, including an older approved version of a managed asset.
        old_aggregate = (
            b"/* Zen Mods - Generated by ZenMods.\n"
            b"* FILE GENERATED AT: Tuesday, November 17, 2026 at 2:00:00 PM GMT\n"
            b"* DO NOT EDIT THIS FILE DIRECTLY!\n"
            b"* Your changes will be overwritten.\n"
            b"* Instead, go to the preferences and edit the mods there.\n"
            b"*/\n"
            b"\n/* Name: Extra */\n/* Description: Kept */\n/* Author: @Other */\n"
            + extra_css
            + b"\n/* Name: old name */\n/* Description: undefined */\n/* Author: @undefined */\n"
            + self.a_old
            + b"\n/* End of Zen Mods */\n"
        )
        aggregate.write_bytes(old_aggregate)
        self.call("check")
        result = self.call("apply")
        self.assertIn("saved replaced files", result.stdout)
        backup = next(self.backups.iterdir())
        self.assertEqual(
            (backup / "chrome" / "zen-themes" / A / "chrome.css").read_bytes(),
            self.a_old,
        )
        self.assertEqual((backup / "zen-themes.json").read_bytes(), original_registry)
        self.assertEqual(
            (backup / "chrome" / "zen-themes.css").read_bytes(),
            old_aggregate,
        )
        report = json.loads((backup / "backup-manifest.json").read_text())
        self.assertIn(f"chrome/zen-themes/{B}/chrome.css", report["created"])
        self.assertEqual(
            report["originalModes"]["zen-themes.json"], f"{original_mode:04o}"
        )
        self.assertEqual(old_css.read_bytes(), self.a_css)
        merged = json.loads((self.profile / "zen-themes.json").read_text())
        self.assertEqual(list(merged), [A, B, EXTRA, DISABLED])
        self.assertTrue(merged[A]["enabled"])
        self.assertEqual(merged[A]["customProperty"], {"keep": 1})
        self.assertEqual(merged[EXTRA], registry[EXTRA])
        self.assertFalse(merged[DISABLED]["enabled"])
        rendered = aggregate.read_bytes()
        self.assertIn(extra_css, rendered)
        self.assertNotIn(b"disabled extra", rendered)
        self.assertTrue(
            (self.profile / "chrome" / "zen-themes" / LEFTOVER / "notes.txt").exists()
        )
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)

    def test_unknown_aggregate_is_not_overwritten_even_with_a_generated_header(self):
        self.call("apply")
        aggregate = self.profile / "chrome" / "zen-themes.css"
        generated = aggregate.read_bytes()
        # Exercise refusal when no lock file has been created yet, too.
        (self.profile / ".parentlock").unlink()
        custom = b".personal { color: red; }\n"
        for contents in (
            custom,
            generated.replace(b"/* End of Zen Mods */", custom + b"/* End of Zen Mods */"),
            generated.replace(
                b"NixOS-Dotfiles reconciliation", b"*/ " + custom.strip() + b" /*"
            ),
        ):
            with self.subTest(css=contents):
                aggregate.write_bytes(contents)
                before = tree(self.profile)
                for mode in ("check", "apply"):
                    result = self.call(mode, ok=False)
                    self.assertIn("does not match generated Zen Mods CSS", result.stderr)
                    self.assertEqual(tree(self.profile), before)
                    self.assertFalse(self.backups.exists())

    def test_generated_empty_aggregate_from_disabling_all_mods_can_be_replaced(self):
        self.call("apply")
        aggregate = self.profile / "chrome" / "zen-themes.css"
        generated = aggregate.read_bytes()
        empty = zen.stylesheet({}, {})
        aggregate.write_bytes(empty)
        self.call("check")
        self.call("apply")
        self.assertEqual(aggregate.read_bytes(), generated)
        backup = next(self.backups.iterdir())
        self.assertEqual((backup / "chrome" / "zen-themes.css").read_bytes(), empty)

    def test_unknown_local_hash_stops_check_and_apply_without_data_loss(self):
        path = self.mod_file(A, "chrome.css", b"local custom CSS")
        (self.profile / ".parentlock").touch()
        before = tree(self.profile)
        for mode in ("check", "apply"):
            result = self.call(mode, ok=False)
            self.assertIn("unexpected SHA-256", result.stderr)
            self.assertIn(sha(b"local custom CSS"), result.stderr)
            self.assertEqual(tree(self.profile), before)
        self.assertEqual(path.read_bytes(), b"local custom CSS")
        self.assertFalse(self.backups.exists())

    def test_refuses_file_and_directory_symlinks_without_touching_targets(self):
        outside = self.base / "outside"
        outside.write_bytes(b"valuable outside file")
        path = self.profile / "zen-themes.json"
        path.symlink_to(outside)
        result = self.call("check", ok=False)
        self.assertIn("regular file", result.stderr)
        self.assertEqual(outside.read_bytes(), b"valuable outside file")
        path.unlink()
        path.symlink_to(self.base / "dangling")
        self.call("check", ok=False)
        self.assertTrue(path.is_symlink())
        path.unlink()

        chrome = self.profile / "chrome"
        external_dir = self.base / "external chrome"
        external_dir.mkdir()
        chrome.symlink_to(external_dir, target_is_directory=True)
        self.call("check", ok=False)
        self.assertEqual(list(external_dir.iterdir()), [])
        chrome.unlink()
        chrome.mkdir()
        mod_dir = chrome / "zen-themes" / A
        mod_dir.parent.mkdir()
        mod_dir.mkdir()
        (mod_dir / "chrome.css").symlink_to(outside)
        self.call("check", ok=False)
        self.assertEqual(outside.read_bytes(), b"valuable outside file")

    def test_foreign_backup_root_is_not_followed(self):
        self.backups.parent.mkdir(parents=True)
        outside = self.base / "outside-backups"
        outside.mkdir()
        self.backups.symlink_to(outside, target_is_directory=True)
        result = self.call("check", ok=False)
        self.assertIn("not a file or symlink", result.stderr)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertEqual(tree(self.profile), {})

    def test_invalid_registry_state_or_missing_extra_css_stops(self):
        reg = self.profile / "zen-themes.json"
        for bad in (b"not JSON", b"[]", b'{"x":1,"x":2}'):
            reg.write_bytes(bad)
            self.call("check", ok=False)
            self.assertEqual(reg.read_bytes(), bad)
        reg.unlink()
        state = self.profile / zen.STATE
        state.write_text('{"schema": 99, "managed": {}}')
        self.call("check", ok=False)
        state.unlink()
        self.registry({EXTRA: {"id": EXTRA, "enabled": True}})
        result = self.call("check", ok=False)
        self.assertIn("directory is missing", result.stderr)
        (self.profile / "chrome" / "zen-themes" / EXTRA).mkdir(parents=True)
        result = self.call("check", ok=False)
        self.assertIn("no stylesheet", result.stderr)

    def test_actual_posix_lock_and_legacy_lock_prevent_reconciliation(self):
        lock = self.profile / ".parentlock"
        lock.touch()
        child = subprocess.Popen(
            [
                sys.executable,
                "-u",
                "-c",
                "import fcntl,sys,time; f=open(sys.argv[1], 'w'); "
                "fcntl.lockf(f, fcntl.LOCK_EX); print('locked', flush=True); time.sleep(30)",
                str(lock),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            self.assertEqual(child.stdout.readline().strip(), "locked")
            before = tree(self.profile)
            for mode in ("check", "apply"):
                result = self.call(mode, ok=False)
                self.assertIn("close all Zen processes", result.stderr)
                self.assertEqual(tree(self.profile), before)
        finally:
            child.terminate()
            child.wait(timeout=5)
            child.stdout.close()
            child.stderr.close()
        legacy = self.profile / "lock"
        legacy.symlink_to("127.0.0.1:+123456")
        result = self.call("apply", ok=False)
        self.assertIn("legacy Zen lock exists", result.stderr)
        self.assertTrue(legacy.is_symlink())

    def test_upstream_cleanup_marker_blocks_before_prefs_can_be_touched(self):
        (self.profile / "prefs.js").write_bytes(b"keep these prefs")
        for name in zen.UPSTREAM_MARKERS:
            marker = self.profile / name
            marker.symlink_to(self.base / "missing")
            result = self.call("check", ok=False)
            self.assertIn("upstream prefs.js cleanup", result.stderr)
            self.assertTrue(marker.is_symlink())
            self.assertEqual(
                (self.profile / "prefs.js").read_bytes(), b"keep these prefs"
            )
            marker.unlink()

    def test_upgrade_uses_previous_recorded_hash_but_rejects_new_manual_edit(self):
        self.call("apply")
        new_css = b"/* next pinned release */\n"
        self.write_source("a.css", new_css)
        self.manifest[0]["files"]["chrome.css"] = self.file("a.css", new_css)
        self.manifest[0]["entry"]["version"] = "2.0"
        self.save_manifest()
        self.call("apply")
        path = self.profile / "chrome" / "zen-themes" / A / "chrome.css"
        self.assertEqual(path.read_bytes(), new_css)
        backup = next(self.backups.iterdir())
        self.assertEqual(
            (backup / "chrome" / "zen-themes" / A / "chrome.css").read_bytes(),
            self.a_css,
        )
        path.write_bytes(b"user changed this")
        before = tree(self.profile)
        self.call("apply", ok=False)
        self.assertEqual(tree(self.profile), before)
        self.assertEqual(path.read_bytes(), b"user changed this")

    def test_removed_manifest_entries_are_never_deleted(self):
        self.call("apply")
        old_b = self.profile / "chrome" / "zen-themes" / B / "chrome.css"
        self.manifest = self.manifest[:1]
        self.save_manifest()
        self.call("apply")
        self.assertEqual(old_b.read_bytes(), self.b_css)
        self.assertIn(B, json.loads((self.profile / "zen-themes.json").read_text()))
        self.assertIn(B, json.loads((self.profile / zen.STATE).read_text())["managed"])

    def test_failed_commit_rolls_back_and_keeps_unique_backup(self):
        self.call("apply")
        for name, data, index in (("a.css", b"new A", 0), ("b.css", b"new B", 1)):
            self.write_source(name, data)
            self.manifest[index]["files"]["chrome.css"] = self.file(name, data)
        self.save_manifest()
        before = tree(self.profile)
        with zen.profile_lock(self.profile, create=False):
            writes, watches = zen.plan(self.profile, zen.load_mods(self.manifest_path))
            real_replace = os.replace
            calls = 0

            def fail_second(src, dest):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("simulated disk failure")
                return real_replace(src, dest)

            with mock.patch.object(zen.os, "replace", side_effect=fail_second):
                with self.assertRaisesRegex(zen.AdoptionError, "rolled back"):
                    zen.apply(self.profile, self.backups, writes, watches)
        self.assertEqual(tree(self.profile), before)
        self.assertEqual(len(list(self.backups.iterdir())), 1)
        self.assertFalse(list(self.profile.rglob(".nixos-dotfiles-zen-*")))

    def test_changes_detected_between_preflight_and_commit_are_not_overwritten(self):
        self.call("apply")
        new_a = b"new A"
        self.write_source("a.css", new_a)
        self.manifest[0]["files"]["chrome.css"] = self.file("a.css", new_a)
        self.save_manifest()
        victim = self.profile / "zen-themes.json"
        with zen.profile_lock(self.profile, create=False):
            writes, watches = zen.plan(self.profile, zen.load_mods(self.manifest_path))
            real_make_temp = zen.make_temp
            changed = False

            def change_during_staging(*args):
                nonlocal changed
                result = real_make_temp(*args)
                if not changed:
                    victim.write_bytes(b"external edit during reconciliation")
                    changed = True
                return result

            with mock.patch.object(zen, "make_temp", side_effect=change_during_staging):
                with self.assertRaisesRegex(zen.AdoptionError, "file changed"):
                    zen.apply(self.profile, self.backups, writes, watches)
        self.assertEqual(victim.read_bytes(), b"external edit during reconciliation")
        self.assertEqual(
            (self.profile / "chrome" / "zen-themes" / A / "chrome.css").read_bytes(),
            self.a_css,
        )

    @unittest.skipUnless(
        os.environ.get("ZEN_PINNED_MODS_MANIFEST"), "no resolved pinned manifest"
    )
    def test_actual_pinned_assets_install_in_a_disposable_profile(self):
        self.manifest_path = Path(os.environ["ZEN_PINNED_MODS_MANIFEST"])
        mods = zen.load_mods(self.manifest_path)
        self.assertEqual(len(mods), 10)
        self.assertEqual(sum(len(files) for _, files, _ in mods), 17)
        self.call("check")
        self.call("apply")
        registry = json.loads((self.profile / "zen-themes.json").read_text())
        self.assertEqual(list(registry), [entry["id"] for entry, _, _ in mods])
        self.assertTrue(all(entry["enabled"] for entry in registry.values()))
        self.assertIn("already reconciled", self.call("apply").stdout)

    def test_bad_pinned_source_is_rejected_before_writes(self):
        self.write_source("a.css", b"tampered download")
        before = tree(self.profile)
        result = self.call("check", ok=False)
        self.assertIn("pinned source hash mismatch", result.stderr)
        self.assertEqual(tree(self.profile), before)


if __name__ == "__main__":
    unittest.main()
