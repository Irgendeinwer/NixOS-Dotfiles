#!/usr/bin/env python3
"""Offline and loopback HTTP integration tests for pkgs/scripts/plan.py."""

from __future__ import annotations

import datetime as dt
import html
import importlib.util
import io
import json
import math
import os
import sys
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock
from zoneinfo import ZoneInfo

sys.dont_write_bytecode = True

PLAN_PATH = Path(
    os.environ.get(
        "JUNIX_PLAN_HELPER",
        Path(__file__).resolve().parents[1] / "pkgs/scripts/plan.py",
    )
)
spec = importlib.util.spec_from_file_location("junix_plan", PLAN_PATH)
assert spec and spec.loader
plan_mod = importlib.util.module_from_spec(spec)
sys.modules["junix_plan"] = plan_mod
spec.loader.exec_module(plan_mod)

TZ = ZoneInfo("Europe/Berlin")


class MockSyncState:
    def __init__(self, max_items_per_page: int = 50) -> None:
        self.projects: dict[int, dict] = {1: {"id": 1, "title": "Inbox"}}
        self.next_proj_id = 2
        self.tasks: dict[int, dict] = {}
        self.next_task_id = 100
        self.relations: list[tuple[int, int, str]] = []
        self.calendars: set[str] = set()
        self.ics_objects: dict[str, str] = {}
        self.max_items_per_page = max_items_per_page
        self.on_request: object = None


class MockPlannerHandler(BaseHTTPRequestHandler):
    state: MockSyncState

    def log_message(self, _fmt: str, *_args: object) -> None:
        return

    def _notify_request(self) -> None:
        cb = getattr(self.state, "on_request", None)
        if callable(cb):
            cb(self.command, self.path)

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length") or "0")
        return self.rfile.read(length) if length > 0 else b""

    def _json(
        self, code: int, payload: object, extra_headers: dict[str, str] | None = None
    ) -> None:
        raw = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        if extra_headers:
            for hk, hv in extra_headers.items():
                self.send_header(hk, hv)
        self.end_headers()
        self.wfile.write(raw)

    def _paginate(self, items: list[dict]) -> tuple[list[dict], dict[str, str]]:
        parsed = urllib.parse.urlsplit(self.path)
        qs = urllib.parse.parse_qs(parsed.query)
        req_per = int(qs.get("per_page", [str(self.state.max_items_per_page)])[0])
        per_page = max(1, min(req_per, self.state.max_items_per_page))
        page = max(1, int(qs.get("page", ["1"])[0]))
        total_pages = max(1, math.ceil(len(items) / per_page)) if items else 1
        start = (page - 1) * per_page
        sliced = items[start : start + per_page]
        return sliced, {
            "x-pagination-total-pages": str(total_pages),
            "x-pagination-result-count": str(len(sliced)),
        }

    def _serialize_task(self, tid: int, t: dict) -> dict:
        copy = dict(t)
        subtasks = [
            {"id": cid}
            for pid, cid, kind in self.state.relations
            if pid == tid and kind == "subtask"
        ]
        parents = [
            {"id": pid}
            for pid, cid, kind in self.state.relations
            if cid == tid and kind == "subtask"
        ]
        copy["related_tasks"] = {"subtask": subtasks, "parenttask": parents}
        return copy

    def do_GET(self) -> None:
        self._notify_request()
        parsed_path = urllib.parse.urlsplit(self.path).path
        if parsed_path == "/api/v1/user":
            self._json(200, {"id": 1, "username": "julian"})
            return
        if parsed_path == "/api/v1/projects":
            batch, hdrs = self._paginate(list(self.state.projects.values()))
            self._json(200, batch, hdrs)
            return
        if parsed_path == "/api/v1/tasks":
            items = [
                self._serialize_task(tid, t)
                for tid, t in sorted(self.state.tasks.items())
            ]
            batch, hdrs = self._paginate(items)
            self._json(200, batch, hdrs)
            return
        if parsed_path.startswith("/api/v1/tasks/"):
            parts = parsed_path.strip("/").split("/")
            if len(parts) == 4 and parts[3].isdigit():
                tid = int(parts[3])
                if tid in self.state.tasks:
                    self._json(200, self._serialize_task(tid, self.state.tasks[tid]))
                    return
        self.send_error(404)

    def do_PUT(self) -> None:
        self._notify_request()
        body = self._read_body()
        if self.path == "/api/v1/projects":
            data = json.loads(body.decode("utf-8"))
            pid = self.state.next_proj_id
            self.state.next_proj_id += 1
            proj = {"id": pid, "title": data["title"]}
            self.state.projects[pid] = proj
            self._json(201, proj)
            return
        if self.path.startswith("/api/v1/projects/") and self.path.endswith("/tasks"):
            pid = int(self.path.split("/")[4])
            data = json.loads(body.decode("utf-8"))
            tid = self.state.next_task_id
            self.state.next_task_id += 1
            task = {
                "id": tid,
                "project_id": pid,
                "title": data["title"],
                "description": data.get("description", ""),
                "done": bool(data.get("done")),
                "priority": int(data.get("priority", 0)),
                "due_date": data.get("due_date", "0001-01-01T00:00:00Z"),
                "start_date": data.get("start_date", "0001-01-01T00:00:00Z"),
                "end_date": data.get("end_date", "0001-01-01T00:00:00Z"),
                "hex_color": data.get("hex_color", ""),
                "is_favorite": bool(data.get("is_favorite", False)),
                "repeat_after": int(data.get("repeat_after", 0)),
                "repeat_mode": int(data.get("repeat_mode", 0)),
                "percent_done": float(data.get("percent_done", 0.0)),
                "updated": "2026-11-20T12:00:00Z",
            }
            self.state.tasks[tid] = task
            self._json(201, task)
            return
        if self.path.startswith("/api/v1/tasks/") and self.path.endswith("/relations"):
            tid = int(self.path.split("/")[4])
            data = json.loads(body.decode("utf-8"))
            rel = (tid, int(data["other_task_id"]), data["relation_kind"])
            if rel not in self.state.relations:
                self.state.relations.append(rel)
            self._json(201, {"task_id": tid, **data})
            return
        if self.path.endswith(".ics"):
            self.state.ics_objects[self.path] = body.decode("utf-8")
            self.send_response(201)
            self.send_header("ETag", f'"etag-{len(body)}"')
            self.end_headers()
            return
        self.send_error(404)

    def do_POST(self) -> None:
        self._notify_request()
        body = self._read_body()
        if self.path.startswith("/api/v1/tasks/"):
            tid = int(self.path.split("/")[4])
            data = json.loads(body.decode("utf-8"))
            if tid not in self.state.tasks:
                self.send_error(404)
                return
            # Match upstream Vikunja UpdateWeb: omitted fields bind to Go zero values!
            self.state.tasks[tid] = {
                "id": tid,
                "project_id": int(data.get("project_id") or self.state.tasks[tid]["project_id"]),
                "title": data.get("title", ""),
                "description": data.get("description", ""),
                "done": bool(data.get("done", False)),
                "priority": int(data.get("priority", 0)),
                "due_date": data.get("due_date", "0001-01-01T00:00:00Z"),
                "start_date": data.get("start_date", "0001-01-01T00:00:00Z"),
                "end_date": data.get("end_date", "0001-01-01T00:00:00Z"),
                "hex_color": data.get("hex_color", ""),
                "is_favorite": bool(data.get("is_favorite", False)),
                "repeat_after": int(data.get("repeat_after", 0)),
                "repeat_mode": int(data.get("repeat_mode", 0)),
                "percent_done": float(data.get("percent_done", 0.0)),
                "updated": "2026-11-20T12:05:00Z",
            }
            self._json(200, self.state.tasks[tid])
            return
        self.send_error(404)

    def do_DELETE(self) -> None:
        self._notify_request()
        if self.path.startswith("/api/v1/tasks/"):
            tid = int(self.path.split("/")[4])
            self.state.tasks.pop(tid, None)
            self._json(200, {"message": "deleted"})
            return
        if self.path.endswith(".ics"):
            self.state.ics_objects.pop(self.path, None)
            self.send_response(204)
            self.end_headers()
            return
        self.send_error(404)

    def do_PROPFIND(self) -> None:
        self._notify_request()
        _ = self._read_body()
        if self.path in self.state.calendars:
            self.send_response(207)
            self.end_headers()
        else:
            self.send_error(404)

    def do_MKCALENDAR(self) -> None:
        self._notify_request()
        _ = self._read_body()
        self.state.calendars.add(self.path)
        self.send_response(201)
        self.end_headers()

    def do_REPORT(self) -> None:
        self._notify_request()
        _ = self._read_body()
        items_xml = []
        for href, cdata in self.state.ics_objects.items():
            if href.startswith(self.path):
                esc = (
                    cdata.replace("&", "&amp;")
                    .replace("<", "&lt;")
                    .replace(">", "&gt;")
                )
                items_xml.append(
                    f"<D:response><D:href>{href}</D:href>"
                    "<D:propstat><D:prop>"
                    '<D:getetag>"v1"</D:getetag>'
                    f"<C:calendar-data>{esc}</C:calendar-data>"
                    "</D:prop></D:propstat></D:response>"
                )
        doc = (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
            + "".join(items_xml)
            + "</D:multistatus>"
        ).encode("utf-8")
        self.send_response(207)
        self.send_header("Content-Type", "application/xml; charset=utf-8")
        self.send_header("Content-Length", str(len(doc)))
        self.end_headers()
        self.wfile.write(doc)


class PlanEngineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.cfg = plan_mod.PlanConfig(
            vikunja_url="",
            radicale_url="",
            timezone="Europe/Berlin",
            config_dir=root / "config",
            data_dir=root / "data",
            runtime_dir=root / "run",
        )
        self.store = plan_mod.PlanStore(self.cfg)
        self.addCleanup(self.store.close)
        self.ref = dt.datetime(2026, 11, 20, 13, 0, tzinfo=TZ)  # Friday

    def test_quick_capture_parses_steps_priority_project_and_times(self) -> None:
        cap = plan_mod.parse_quick_capture(
            "+ Prepare seminar talk tomorrow 16:00 !high #uni >> Read paper ~30m >> Build slides ~45m >> Rehearse ~20m",
            self.ref,
        )
        self.assertEqual(cap.kind, "task")
        self.assertEqual(cap.title, "Prepare seminar talk")
        self.assertEqual(cap.project, "uni")
        self.assertEqual(cap.priority, 3)
        self.assertEqual(cap.estimate_min, 95)
        self.assertEqual(cap.due_at, dt.datetime(2026, 11, 21, 16, 0, tzinfo=TZ))
        self.assertEqual([s.title for s in cap.steps], ["Read paper", "Build slides", "Rehearse"])
        self.assertEqual([s.estimate_min for s in cap.steps], [30, 45, 20])

        ev = plan_mod.parse_quick_capture(
            "@ Dentist 24.11.2026 14:30-15:15 @City_Clinic weekly",
            self.ref,
        )
        self.assertEqual(ev.kind, "event")
        self.assertEqual(ev.title, "Dentist")
        self.assertEqual(ev.location, "City Clinic")
        self.assertEqual(ev.rrule, "FREQ=WEEKLY")
        self.assertEqual(ev.start_at, dt.datetime(2026, 11, 24, 14, 30, tzinfo=TZ))
        self.assertEqual(ev.end_at, dt.datetime(2026, 11, 24, 15, 15, tzinfo=TZ))

    def test_time_aware_step_slotter_fits_gaps_and_preserves_step_order(self) -> None:
        # Appointment from 14:00 to 15:00 -> with 5m buffer, first free gap is 13:00..13:55 (55m)
        ev_cap = plan_mod.parse_quick_capture("@ Seminar today 14:00-15:00 @Room101", self.ref)
        self.store.add_captured_event(ev_cap, self.ref)

        # Parent task with Step 1 (30m) + Step 2 (40m); plus a quick 15m errand
        t_cap = plan_mod.parse_quick_capture(
            "+ Linear Algebra today 20:00 !urgent #uni >> Read theorems ~30m >> Solve sheet ~40m",
            self.ref,
        )
        self.store.add_captured_task(t_cap, self.ref)

        q_cap = plan_mod.parse_quick_capture("+ Reply to tutor today 21:00 ~15m !high #uni", self.ref)
        self.store.add_captured_task(q_cap, self.ref)

        day = plan_mod.compute_day_plan(self.store, self.ref)
        self.assertEqual(len(day.appointments), 1)
        # First gap is 13:00..13:55 (55m):
        # Step 1 ("Read theorems", 30m) slots 13:00..13:30 (+5m -> 13:35, leaving 20m).
        # Step 2 ("Solve sheet", 40m) does NOT fit in 20m, so "Reply to tutor" (15m) smartly fills 13:35..13:50!
        # Then after Seminar + 5m buffer (15:05), Step 2 ("Solve sheet", 40m) slots 15:05..15:45!
        self.assertEqual(len(day.slotted), 3)
        self.assertEqual(day.slotted[0].title, "Read theorems")
        self.assertEqual(day.slotted[0].step_badge, "[1/2]")
        self.assertEqual(day.slotted[0].start.strftime("%H:%M"), "13:00")

        self.assertEqual(day.slotted[1].title, "Reply to tutor")
        self.assertEqual(day.slotted[1].start.strftime("%H:%M"), "13:35")

        self.assertEqual(day.slotted[2].title, "Solve sheet")
        self.assertEqual(day.slotted[2].step_badge, "[2/2]")
        self.assertEqual(day.slotted[2].start.strftime("%H:%M"), "15:05")

    def test_rrule_weekly_and_exdate_expansion(self) -> None:
        ics = (
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n"
            "UID:lec-1\r\nSUMMARY:Operating Systems\r\n"
            "DTSTART;TZID=Europe/Berlin:20261106T100000\r\n"
            "DTEND;TZID=Europe/Berlin:20261106T113000\r\n"
            "RRULE:FREQ=WEEKLY;BYDAY=FR\r\n"
            "EXDATE;TZID=Europe/Berlin:20261113T100000\r\n"
            "END:VEVENT\r\nEND:VCALENDAR\r\n"
        )
        evs = plan_mod.parse_ics_events(ics, TZ)
        self.assertEqual(len(evs), 1)
        # 2026-11-13 is excluded by EXDATE
        self.assertEqual(plan_mod.expand_event_on_date(evs[0], dt.date(2026, 11, 13), TZ), [])
        # 2026-11-20 matches weekly Friday
        occ = plan_mod.expand_event_on_date(evs[0], dt.date(2026, 11, 20), TZ)
        self.assertEqual(len(occ), 1)
        self.assertEqual(occ[0][0].strftime("%H:%M"), "10:00")
        self.assertEqual(occ[0][1].strftime("%H:%M"), "11:30")

    def test_focus_dnd_ownership_and_lock_status_escaping(self) -> None:
        cap = plan_mod.parse_quick_capture("+ Write <parser> & tests ~20m", self.ref)
        key = self.store.add_captured_task(cap, self.ref)

        dnd_state = {"on": False}

        def fake_is_dnd() -> bool:
            return dnd_state["on"]

        def fake_set_dnd(enable: bool) -> None:
            dnd_state["on"] = enable

        with (
            mock.patch.object(plan_mod, "is_mako_dnd_active", side_effect=fake_is_dnd),
            mock.patch.object(plan_mod, "set_mako_dnd", side_effect=fake_set_dnd),
            mock.patch.object(plan_mod, "show_osd"),
        ):
            plan_mod.focus_start(self.store, key, self.ref)
            self.assertTrue(dnd_state["on"])
            lock_txt = self.cfg.lock_status_path.read_text(encoding="utf-8").strip()
            self.assertIn("&lt;parser&gt; &amp;", lock_txt)
            plan_mod.focus_stop(self.store, self.ref, mark_done=True)
            # Focus owned DND, so stopping restores DND=False
            self.assertFalse(dnd_state["on"])
            self.assertEqual(self.store.get_task(key)["done"], 1)

            # Now test manual DND already active before Focus: Focus must NOT turn it off!
            key2 = self.store.add_captured_task(
                plan_mod.parse_quick_capture("+ Second task ~15m", self.ref), self.ref
            )
            dnd_state["on"] = True
            plan_mod.focus_start(self.store, key2, self.ref)
            plan_mod.focus_stop(self.store, self.ref, mark_done=False)
            self.assertTrue(dnd_state["on"])

    def test_daemon_tick_fires_critical_appointment_and_deduplicates(self) -> None:
        ev_cap = plan_mod.parse_quick_capture("@ Train 13:15-14:00 @Hbf", self.ref)
        self.store.add_captured_event(ev_cap, self.ref)
        with mock.patch.object(plan_mod, "_spawn_action_notification"):
            fired1 = plan_mod.daemon_tick(self.store, self.ref)
            fired2 = plan_mod.daemon_tick(self.store, self.ref)
        self.assertEqual(len(fired1), 1)
        self.assertEqual(fired1[0][0], "critical")
        self.assertIn("In 15m: Train", fired1[0][1])
        self.assertEqual(fired2, [])

    def test_offline_queue_syncs_roundtrip_with_vikunja_and_radicale(self) -> None:
        mock_state = MockSyncState()

        class BoundHandler(MockPlannerHandler):
            state = mock_state

        server = ThreadingHTTPServer(("127.0.0.1", 0), BoundHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)

        base_url = f"http://127.0.0.1:{server.server_port}"
        self.cfg.vikunja_url = base_url
        self.cfg.vikunja_token = "tk_test_123"
        self.cfg.radicale_url = base_url
        self.cfg.radicale_user = "julian"
        self.cfg.radicale_password = "secret"

        # Capture offline first
        parent_key = self.store.add_captured_task(
            plan_mod.parse_quick_capture(
                "+ Thesis chapter #research !urgent >> Literature ~30m >> Draft ~50m",
                self.ref,
            ),
            self.ref,
        )
        ev_uid = self.store.add_captured_event(
            plan_mod.parse_quick_capture("@ Advisor Meeting tomorrow 11:00-12:00 @Zoom", self.ref),
            self.ref,
        )

        res = plan_mod.sync_all(self.store, self.ref)
        self.assertEqual(res["errors"], [])
        self.assertEqual(res["vikunja"], "ok")
        self.assertEqual(res["radicale"], "ok")
        # Created 'research' project + 3 tasks (parent + 2 steps) + 2 subtask relations + 1 .ics
        self.assertEqual(len(mock_state.tasks), 3)
        self.assertEqual(len(mock_state.relations), 2)
        self.assertEqual(len(mock_state.ics_objects), 1)

        # Simulate fresh second machine (e.g. junixbook pulling from junixsrv!)
        root2 = Path(self.tmp.name) / "laptop"
        cfg2 = plan_mod.PlanConfig(
            vikunja_url=base_url,
            vikunja_token="tk_test_123",
            radicale_url=base_url,
            radicale_user="julian",
            radicale_password="secret",
            timezone="Europe/Berlin",
            config_dir=root2 / "cfg",
            data_dir=root2 / "data",
            runtime_dir=root2 / "run",
        )
        store2 = plan_mod.PlanStore(cfg2)
        self.addCleanup(store2.close)
        res2 = plan_mod.sync_all(store2, self.ref)
        self.assertEqual(res2["errors"], [])
        pulled_tasks = store2.active_tasks()
        self.assertEqual(len(pulled_tasks), 3)
        steps = [r for r in pulled_tasks if r["parent_key"] is not None]
        self.assertEqual(len(steps), 2)
        self.assertEqual(sorted(int(r["estimate_min"]) for r in steps), [30, 50])
        self.assertEqual(len(store2.active_events()), 1)
        self.assertEqual(store2.active_events()[0].uid, ev_uid)

        # Delete on desktop and verify deletion propagates
        self.store.delete_item(parent_key, self.ref)
        self.store.delete_item(ev_uid, self.ref)
        plan_mod.sync_all(self.store, self.ref)
        self.assertEqual(len(mock_state.tasks), 0)
        self.assertEqual(len(mock_state.ics_objects), 0)

    def test_parser_default_project_semver_and_leading_event_number(self) -> None:
        cap = plan_mod.parse_quick_capture(
            "+ Ship v1.2.20 release notes ~20m",
            self.ref,
            default_project="Work",
        )
        self.assertEqual(cap.project, "Work")
        self.assertEqual(cap.title, "Ship v1.2.20 release notes")
        self.assertIsNone(cap.due_at)

        cap_num = plan_mod.parse_quick_capture("+ Bump 1.2.20 dependency", self.ref)
        self.assertEqual(cap_num.title, "Bump 1.2.20 dependency")
        self.assertIsNone(cap_num.due_at)

        ev = plan_mod.parse_quick_capture("@ 100m Sprint 14:00 30m @Track", self.ref)
        self.assertEqual(ev.title, "100m Sprint")
        self.assertEqual(ev.estimate_min, 30)
        self.assertEqual(ev.start_at, dt.datetime(2026, 11, 20, 14, 0, tzinfo=TZ))
        self.assertEqual(ev.end_at, dt.datetime(2026, 11, 20, 14, 30, tzinfo=TZ))

    def test_recurrence_id_override_and_cancelled_instance_exclude_master(self) -> None:
        ics = (
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
            "BEGIN:VEVENT\r\n"
            "UID:weekly-sync\r\nSUMMARY:Weekly Sync\r\n"
            "DTSTART;TZID=Europe/Berlin:20261106T100000\r\n"
            "DTEND;TZID=Europe/Berlin:20261106T110000\r\n"
            "RRULE:FREQ=WEEKLY;BYDAY=FR\r\n"
            "END:VEVENT\r\n"
            "BEGIN:VEVENT\r\n"
            "UID:weekly-sync\r\n"
            "RECURRENCE-ID;TZID=Europe/Berlin:20261120T100000\r\n"
            "SUMMARY:Weekly Sync (Moved)\r\n"
            "DTSTART;TZID=Europe/Berlin:20261120T150000\r\n"
            "DTEND;TZID=Europe/Berlin:20261120T160000\r\n"
            "END:VEVENT\r\n"
            "BEGIN:VEVENT\r\n"
            "UID:weekly-sync\r\n"
            "RECURRENCE-ID;TZID=Europe/Berlin:20261127T100000\r\n"
            "STATUS:CANCELLED\r\n"
            "DTSTART;TZID=Europe/Berlin:20261127T100000\r\n"
            "END:VEVENT\r\n"
            "END:VCALENDAR\r\n"
        )
        self.store.import_ics_text(ics, self.ref)
        day_moved = plan_mod.compute_day_plan(self.store, self.ref)
        # Only the moved 15:00-16:00 override appears on 2026-11-20 (no duplicate 10:00 master!)
        self.assertEqual(len(day_moved.appointments), 1)
        self.assertEqual(day_moved.appointments[0].title, "Weekly Sync (Moved)")
        self.assertEqual(day_moved.appointments[0].start.strftime("%H:%M"), "15:00")

        # 2026-11-27 was STATUS:CANCELLED via RECURRENCE-ID -> 0 occurrences
        next_fri = dt.datetime(2026, 11, 27, 9, 0, tzinfo=TZ)
        day_cancelled = plan_mod.compute_day_plan(self.store, next_fri)
        self.assertEqual(day_cancelled.appointments, [])

    def test_commit_day_plan_keeps_auto_slots_flexible_and_preserves_split_estimate(self) -> None:
        # 20m free gap before 13:25..14:30 event -> 45m task splits 20m + 25m
        ev_cap = plan_mod.parse_quick_capture("@ Call today 13:25-14:30", self.ref)
        self.store.add_captured_event(ev_cap, self.ref)
        t_key = self.store.add_captured_task(
            plan_mod.parse_quick_capture("+ Deep review ~45m !high", self.ref),
            self.ref,
        )
        day1 = plan_mod.compute_day_plan(self.store, self.ref)
        self.assertEqual(len(day1.slotted), 2)
        plan_mod.commit_day_plan(self.store, day1, self.ref)
        row = self.store.get_task(t_key)
        self.assertEqual(row["auto_slotted"], 1)

        # Later at 14:35 (still undone), task must dynamically re-slot for its full 45m,
        # NOT freeze as a past 20m fixed_task!
        later = dt.datetime(2026, 11, 20, 14, 35, tzinfo=TZ)
        day2 = plan_mod.compute_day_plan(self.store, later)
        self.assertEqual([b for b in day2.appointments if b.kind == "fixed_task"], [])
        self.assertEqual(len(day2.slotted), 1)
        self.assertEqual(day2.slotted[0].key, t_key)
        self.assertEqual(
            int((day2.slotted[0].end - day2.slotted[0].start).total_seconds() // 60),
            45,
        )

    def test_step_order_never_inverts_and_daemon_deduplicates_parent_and_steps(self) -> None:
        p_key = self.store.add_captured_task(
            plan_mod.parse_quick_capture(
                "+ Project milestone today 13:00 >> Step one ~20m >> Step two ~20m",
                self.ref,
            ),
            self.ref,
        )
        steps = [r for r in self.store.active_tasks() if r["parent_key"] == p_key]
        steps.sort(key=lambda r: r["step_index"])
        # Give Step 2 higher priority and an earlier due timestamp than Step 1!
        self.store.conn.execute(
            "UPDATE tasks SET priority = 4, due_at = ? WHERE local_key = ?",
            (plan_mod.to_utc_iso(self.ref - dt.timedelta(minutes=10)), steps[1]["local_key"]),
        )
        self.store.conn.execute(
            "UPDATE tasks SET due_at = ? WHERE local_key = ?",
            (plan_mod.to_utc_iso(self.ref), steps[0]["local_key"]),
        )
        self.store.conn.commit()

        day = plan_mod.compute_day_plan(self.store, self.ref)
        self.assertEqual(
            [b.title for b in day.slotted],
            ["Step one", "Step two"],
        )

        # Snoozing Step 1 also holds back Step 2 until Step 1 wakes up
        self.store.snooze_task(
            steps[0]["local_key"], self.ref + dt.timedelta(minutes=30), self.ref
        )
        day_snz = plan_mod.compute_day_plan(self.store, self.ref)
        self.assertEqual(day_snz.slotted, [])

        # Restore Step 1 due now and verify daemon_tick fires ONLY for Step 1 (not parent or Step 2)
        self.store.conn.execute(
            "UPDATE tasks SET snoozed_until = NULL, due_at = ? WHERE local_key = ?",
            (plan_mod.to_utc_iso(self.ref), steps[0]["local_key"]),
        )
        self.store.conn.commit()
        with mock.patch.object(plan_mod, "_spawn_action_notification"):
            fired = plan_mod.daemon_tick(self.store, self.ref)
        self.assertEqual(len(fired), 1)
        self.assertEqual(fired[0][1], "Due: Step one")

    def test_rofi_hub_inline_capture_and_alt_shortcuts(self) -> None:
        t_key = self.store.add_captured_task(
            plan_mod.parse_quick_capture("+ Existing task ~25m", self.ref),
            self.ref,
        )
        with (
            mock.patch.object(plan_mod, "now_local", return_value=self.ref),
            mock.patch.object(plan_mod, "show_osd"),
            mock.patch.object(plan_mod, "opportunistic_background_sync"),
        ):
            # Typing "+ Buy milk ~10m" while row 0 is still highlighted (idx=0, rc=0) must capture!
            with mock.patch.object(
                plan_mod,
                "_rofi_prompt",
                return_value=(0, 0, "+ Buy milk ~10m", "Existing row"),
            ):
                plan_mod.run_rofi_hub(self.store)
            titles = {r["title"] for r in self.store.active_tasks()}
            self.assertIn("Buy milk", titles)

            # Pressing Alt+2 (rc=11) on Existing task snoozes it +15m
            with mock.patch.object(
                plan_mod,
                "_rofi_prompt",
                return_value=(11, 0, "", "Existing task"),
            ):
                plan_mod.run_rofi_hub(self.store)
            snz = plan_mod.from_iso(self.store.get_task(t_key)["snoozed_until"], TZ)
            self.assertEqual(snz, self.ref + dt.timedelta(minutes=15))

    def test_description_tag_unanchored_html_and_cmd_auth_safe_write(self) -> None:
        clean, est, step, auto = plan_mod.decode_task_description(
            "<p>Notes before</p><p><!-- junix-plan:{\"est\":35,\"step\":2,\"auto\":1} --></p><p>Web UI note</p>"
        )
        self.assertEqual(est, 35)
        self.assertEqual(step, 2)
        self.assertTrue(auto)
        self.assertIn("Notes before", clean)
        self.assertIn("Web UI note", clean)
        self.assertNotIn("junix-plan", clean)

        # Verify cmd_auth writes only secrets to config_dir/credentials.env and never touches read-only credentials_file
        ro_secret = Path(self.tmp.name) / "ro-sops.env"
        ro_secret.write_text("RADICALE_PASSWORD=from_sops\n", encoding="utf-8")
        ro_secret.chmod(0o400)
        self.addCleanup(lambda: ro_secret.chmod(0o600))
        self.cfg.credentials_file = str(ro_secret)
        self.cfg.vikunja_url = "https://tasks.junixsrv.internal"
        self.cfg.radicale_url = "https://cal.junixsrv.internal"

        args = plan_mod.build_parser().parse_args(
            [
                "auth",
                "--vikunja-token",
                "tk_interactive",
                "--radicale-user",
                "julian",
                "--radicale-password",
                "",
            ]
        )
        with (
            mock.patch.object(plan_mod, "load_config", return_value=plan_mod.PlanConfig()),
            mock.patch("sys.stderr"),
            mock.patch("builtins.print"),
        ):
            plan_mod.cmd_auth(self.cfg, args)

        written = (self.cfg.config_dir / "credentials.env").read_text(encoding="utf-8")
        self.assertIn("VIKUNJA_TOKEN=tk_interactive", written)
        self.assertNotIn("VIKUNJA_URL=", written)
        self.assertNotIn("RADICALE_URL=", written)
        self.assertEqual(ro_secret.read_text(encoding="utf-8"), "RADICALE_PASSWORD=from_sops\n")

        # Re-running cmd_auth with blank token ("leave blank to skip") preserves existing VIKUNJA_TOKEN!
        args_skip = plan_mod.build_parser().parse_args(
            [
                "auth",
                "--vikunja-token",
                "",
                "--radicale-user",
                "julian",
                "--radicale-password",
                "new_rad_pw",
            ]
        )
        with (
            mock.patch.object(plan_mod, "load_config", return_value=plan_mod.PlanConfig()),
            mock.patch("sys.stderr"),
            mock.patch("builtins.print"),
        ):
            plan_mod.cmd_auth(self.cfg, args_skip)
        written2 = (self.cfg.config_dir / "credentials.env").read_text(encoding="utf-8")
        self.assertIn("VIKUNJA_TOKEN=tk_interactive", written2)
        self.assertIn("RADICALE_PASSWORD=new_rad_pw", written2)

    def test_vikunja_pagination_cap_50_syncs_all_pages_and_preserves_web_fields(self) -> None:
        mock_state = MockSyncState(max_items_per_page=50)
        for idx in range(1, 66):
            mock_state.tasks[idx] = {
                "id": idx,
                "project_id": 1,
                "title": f"Server task {idx}",
                "description": "",
                "done": False,
                "priority": 1,
                "due_date": "0001-01-01T00:00:00Z",
                "start_date": "0001-01-01T00:00:00Z",
                "end_date": "0001-01-01T00:00:00Z",
                "hex_color": "d8a657" if idx == 55 else "",
                "is_favorite": (idx == 55),
                "repeat_after": 86400 if idx == 55 else 0,
                "repeat_mode": 0,
                "percent_done": 0.5 if idx == 55 else 0.0,
                "updated": "2026-11-20T12:00:00Z",
            }

        tx_states: list[bool] = []
        mock_state.on_request = lambda _m, _p: tx_states.append(self.store.conn.in_transaction)

        class BoundHandler(MockPlannerHandler):
            state = mock_state

        server = ThreadingHTTPServer(("127.0.0.1", 0), BoundHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)

        base_url = f"http://127.0.0.1:{server.server_port}"
        self.cfg.vikunja_url = base_url
        self.cfg.vikunja_token = "tk_paginated"
        self.cfg.radicale_url = base_url
        self.cfg.radicale_user = "julian"
        self.cfg.radicale_password = "secret"

        # First sync pulls all 65 tasks across page 1 (50) + page 2 (15)
        res1 = plan_mod.sync_all(self.store, self.ref)
        self.assertEqual(res1["errors"], [])
        self.assertEqual(len(self.store.active_tasks()), 65)
        self.assertIsNotNone(self.store.get_task("vk-55"))

        # Mark task #55 done locally and sync again:
        # 1) #55 must NOT be pruned on page 2
        # 2) Web-UI fields (hex_color, is_favorite, repeat_after, percent_done) must survive POST!
        # 3) SQLite write transaction must NEVER be open during any HTTP call!
        self.store.mark_task_done("vk-55", self.ref, done=True)
        self.store.add_captured_event(
            plan_mod.parse_quick_capture("@ Sync Check 16:00-16:30", self.ref),
            self.ref,
        )
        tx_states.clear()
        res2 = plan_mod.sync_all(self.store, self.ref)
        self.assertEqual(res2["errors"], [])
        self.assertEqual(len(self.store.active_tasks()), 65)
        self.assertTrue(mock_state.tasks[55]["done"])
        self.assertEqual(mock_state.tasks[55]["hex_color"], "d8a657")
        self.assertTrue(mock_state.tasks[55]["is_favorite"])
        self.assertEqual(mock_state.tasks[55]["repeat_after"], 86400)
        self.assertEqual(mock_state.tasks[55]["percent_done"], 0.5)
        self.assertTrue(tx_states)
        self.assertFalse(any(tx_states), f"SQLite transaction held during HTTP: {tx_states}")

    def test_valarm_subcomponents_ignored_and_import_ics_serializes_exdates(self) -> None:
        ics = (
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
            "BEGIN:VEVENT\r\n"
            "UID:doc-visit\r\n"
            "SUMMARY:Doctor Appointment\r\n"
            "DESCRIPTION:Bring insurance card\r\n"
            "DTSTART;TZID=Europe/Berlin:20261106T090000\r\n"
            "DURATION:PT45M\r\n"
            "RRULE:FREQ=WEEKLY;BYDAY=FR\r\n"
            "EXDATE;TZID=Europe/Berlin:20261113T090000\r\n"
            "BEGIN:VALARM\r\n"
            "ACTION:DISPLAY\r\n"
            "SUMMARY:Alarm Summary\r\n"
            "DESCRIPTION:Reminder\r\n"
            "DURATION:PT5M\r\n"
            "TRIGGER:-PT15M\r\n"
            "END:VALARM\r\n"
            "END:VEVENT\r\n"
            "END:VCALENDAR\r\n"
        )
        count = self.store.import_ics_text(ics, self.ref)
        self.assertEqual(count, 1)
        evs = self.store.active_events()
        self.assertEqual(len(evs), 1)
        self.assertEqual(evs[0].summary, "Doctor Appointment")
        self.assertEqual(evs[0].description, "Bring insurance card")
        self.assertEqual(
            int((evs[0].dtend - evs[0].dtstart).total_seconds() // 60),
            45,
        )
        # Verify serialized raw_ics stored for Radicale upload preserves EXDATE!
        row = self.store.conn.execute(
            "SELECT raw_ics FROM events WHERE uid = 'doc-visit'"
        ).fetchone()
        self.assertIn("EXDATE;TZID=Europe/Berlin:20261113T090000", row["raw_ics"])
        reparsed = plan_mod.parse_ics_events(row["raw_ics"], TZ)
        self.assertIn(dt.date(2026, 11, 13), reparsed[0].exdates)

    def test_stale_focus_notification_ignores_newer_focus_session_and_hud_renders(self) -> None:
        k1 = self.store.add_captured_task(
            plan_mod.parse_quick_capture("+ First step ~15m", self.ref), self.ref
        )
        k2 = self.store.add_captured_task(
            plan_mod.parse_quick_capture("+ Second step ~25m", self.ref), self.ref
        )
        captured_callbacks: list = []

        def fake_spawn(_cfg, _sum, _body, **_kwargs):
            captured_callbacks.append(_kwargs["on_action"])

        with (
            mock.patch.object(plan_mod, "is_mako_dnd_active", return_value=False),
            mock.patch.object(plan_mod, "set_mako_dnd"),
            mock.patch.object(plan_mod, "show_osd"),
            mock.patch.object(plan_mod, "_spawn_action_notification", side_effect=fake_spawn),
        ):
            plan_mod.focus_start(self.store, k1, self.ref)
            # Advance past k1's 15m timer so daemon_tick emits Focus completion
            t_done = self.ref + dt.timedelta(minutes=16)
            plan_mod.daemon_tick(self.store, t_done)
            self.assertEqual(len(captured_callbacks), 1)
            stale_cb = captured_callbacks[0]

            # User finishes k1 via Rofi and immediately starts focusing on k2
            plan_mod.focus_stop(self.store, t_done, mark_done=True)
            plan_mod.focus_start(self.store, k2, t_done + dt.timedelta(seconds=5))

            # Old Mako popup from k1 is dismissed or clicked -> must NOT touch k2!
            stale_cb("dismiss")
            stale_cb("done")
            cur_foc = self.store.get_focus()
            self.assertEqual(cur_foc["active"], 1)
            self.assertEqual(cur_foc["task_key"], k2)
            self.assertEqual(self.store.get_task(k2)["done"], 0)

            # Smoke test Pulse HUD & JSON agenda rendering
            hdr, body = plan_mod.build_pulse_summary(self.store, t_done + dt.timedelta(minutes=1))
            self.assertIn("Focus", hdr)
            self.assertIn("Second step", body)
            buf = io.StringIO()
            with mock.patch("sys.stdout", buf):
                self.assertEqual(plan_mod.cmd_agenda(self.store, as_json=True), 0)
            parsed_json = json.loads(buf.getvalue())
            self.assertEqual(parsed_json["focus"]["task_key"], k2)

    def test_tied_parent_steps_stay_contiguous_and_recommit_clears_bumped_slots(self) -> None:
        self.store.add_captured_task(
            plan_mod.parse_quick_capture(
                "+ Project Alpha !high >> Alpha 1 ~20m >> Alpha 2 ~20m", self.ref
            ),
            self.ref,
        )
        self.store.add_captured_task(
            plan_mod.parse_quick_capture(
                "+ Project Beta !high >> Beta 1 ~20m >> Beta 2 ~20m",
                self.ref + dt.timedelta(seconds=1),
            ),
            self.ref + dt.timedelta(seconds=1),
        )

        day1 = plan_mod.compute_day_plan(self.store, self.ref)
        self.assertEqual(
            [b.title for b in day1.slotted],
            ["Alpha 1", "Alpha 2", "Beta 1", "Beta 2"],
        )
        self.assertEqual(plan_mod.commit_day_plan(self.store, day1, self.ref), 4)

        beta_rows = [
            r for r in self.store.active_tasks() if str(r["title"]).startswith("Beta ")
        ]
        self.assertEqual(len(beta_rows), 2)
        for r in beta_rows:
            self.assertEqual(r["auto_slotted"], 1)
            self.assertIsNotNone(r["start_at"])

        # Add a busy block today leaving 13:00..13:50 (50m free), fitting Alpha 1+2 and bumping Beta 1+2
        self.store.add_captured_event(
            plan_mod.parse_quick_capture("@ Long Workshop today 13:55-22:00", self.ref),
            self.ref,
        )
        day2 = plan_mod.compute_day_plan(self.store, self.ref)
        self.assertEqual([b.title for b in day2.slotted], ["Alpha 1", "Alpha 2"])
        self.assertEqual(plan_mod.commit_day_plan(self.store, day2, self.ref), 2)

        for r in beta_rows:
            refreshed = self.store.get_task(str(r["local_key"]))
            self.assertEqual(refreshed["auto_slotted"], 0)
            self.assertIsNone(refreshed["start_at"])
            self.assertIsNone(refreshed["end_at"])
            self.assertEqual(refreshed["dirty_op"], "upsert")

    def test_focus_extend_ignores_stale_popup_done_next_single_osd_and_done_releases_focus(self) -> None:
        p_key = self.store.add_captured_task(
            plan_mod.parse_quick_capture(
                "+ Thesis !high >> Draft intro ~15m >> Draft eval ~20m", self.ref
            ),
            self.ref,
        )
        steps = [
            r for r in self.store.active_tasks() if r["parent_key"] == p_key
        ]
        steps.sort(key=lambda r: r["step_index"])
        s1_key, s2_key = str(steps[0]["local_key"]), str(steps[1]["local_key"])

        # SQL LIKE wildcards in get_task must never match arbitrary tasks
        self.assertIsNone(self.store.get_task("_"))
        self.assertIsNone(self.store.get_task("%"))

        callbacks: list = []
        dnd_calls: list[bool] = []
        osd_msgs: list[str] = []

        def fake_spawn(_cfg, _sum, _body, **_kwargs):
            callbacks.append(_kwargs["on_action"])

        with (
            mock.patch.object(plan_mod, "is_mako_dnd_active", return_value=False),
            mock.patch.object(plan_mod, "set_mako_dnd", side_effect=dnd_calls.append),
            mock.patch.object(plan_mod, "show_osd", side_effect=osd_msgs.append),
            mock.patch.object(plan_mod, "opportunistic_background_sync"),
            mock.patch.object(plan_mod, "_spawn_action_notification", side_effect=fake_spawn),
        ):
            plan_mod.focus_start(self.store, s1_key, self.ref)
            t1 = self.ref + dt.timedelta(minutes=16)
            plan_mod.daemon_tick(self.store, t1)
            self.assertEqual(len(callbacks), 1)
            first_cb = callbacks[0]

            # Extending via CLI invalidates the earlier completion popup on dismiss
            plan_mod.focus_extend(self.store, 10, t1)
            first_cb("dismiss")
            self.assertEqual(self.store.get_focus()["active"], 1)
            self.assertEqual(self.store.get_focus()["task_key"], s1_key)

            # Now let the extended timer expire and click "done" (Done & Next)
            t2 = t1 + dt.timedelta(minutes=11)
            with mock.patch.object(plan_mod, "now_local", return_value=t2):
                plan_mod.daemon_tick(self.store, t2)
                self.assertEqual(len(callbacks), 2)
                osd_msgs.clear()
                callbacks[1]("done")

            # Exactly ONE OSD message shown when chaining into Step 2
            self.assertEqual(len(osd_msgs), 1)
            self.assertIn("Draft eval", osd_msgs[0])
            self.assertEqual(self.store.get_focus()["active"], 1)
            self.assertEqual(self.store.get_focus()["task_key"], s2_key)

            # Completing the focused task directly (e.g. `plan done`) releases Focus and DND
            dnd_calls.clear()
            self.store.mark_task_done(s2_key, t2 + dt.timedelta(minutes=5), done=True)
            self.assertEqual(self.store.get_focus()["active"], 0)
            self.assertIn(False, dnd_calls)

    def test_ics_quoted_params_until_timestamp_and_backslash_roundtrip(self) -> None:
        raw_ics = (
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
            "BEGIN:VEVENT\r\n"
            "UID:quoted-param-ev\r\n"
            'SUMMARY;ALTREP="https://junix.internal/cal?x=1;y=2":Design Review\r\n'
            'DESCRIPTION;ALTREP="https://junix.internal/doc:v1;raw":Path C:\\\\notes\\nBring slides\r\n'
            "DTSTART;TZID=Europe/Berlin:20261119T110000\r\n"
            "DTEND;TZID=Europe/Berlin:20261119T120000\r\n"
            "RRULE:FREQ=DAILY;UNTIL=20261120T090000Z\r\n"
            "END:VEVENT\r\n"
            "END:VCALENDAR\r\n"
        )
        evs = plan_mod.parse_ics_events(raw_ics, TZ)
        self.assertEqual(len(evs), 1)
        ev = evs[0]
        self.assertEqual(ev.summary, "Design Review")
        self.assertEqual(ev.description, "Path C:\\notes\nBring slides")

        # Round-trip escaping preserves literal "\n" after "\" (`C:\notes`) vs real newline
        rebuilt = plan_mod.build_ics_document(
            uid=ev.uid,
            summary=ev.summary,
            dtstart=ev.dtstart,
            dtend=ev.dtend,
            tz_name="Europe/Berlin",
            description=ev.description,
            rrule=ev.rrule,
        )
        self.assertEqual(
            plan_mod.parse_ics_events(rebuilt, TZ)[0].description,
            "Path C:\\notes\nBring slides",
        )

        # 2026-11-19 11:00 CET (10:00Z <= 2026-11-20T09:00:00Z) matches;
        # 2026-11-20 11:00 CET (10:00Z > 2026-11-20T09:00:00Z) is excluded!
        self.assertEqual(len(plan_mod.expand_event_on_date(ev, dt.date(2026, 11, 19), TZ)), 1)
        self.assertEqual(plan_mod.expand_event_on_date(ev, dt.date(2026, 11, 20), TZ), [])

        # Bare duration tokens before an event clock stay in title; trailing bare duration parses
        ev_room = plan_mod.parse_quick_capture("@ Room 2m 14:00", self.ref)
        self.assertEqual(ev_room.title, "Room 2m")
        self.assertEqual(int((ev_room.end_at - ev_room.start_at).total_seconds() // 60), 60)

        ev_sem = plan_mod.parse_quick_capture(
            "@ Weekly Seminar mon 10:15 90m weekly", self.ref
        )
        self.assertEqual(ev_sem.title, "Weekly Seminar")
        self.assertEqual(ev_sem.rrule, "FREQ=WEEKLY")
        self.assertEqual(int((ev_sem.end_at - ev_sem.start_at).total_seconds() // 60), 90)

        t_custom_est = plan_mod.parse_quick_capture(
            "+ Sheet >> Part 1 >> Part 2", self.ref, default_estimate_minutes=40
        )
        self.assertEqual(t_custom_est.estimate_min, 80)

    def test_lock_pill_three_segment_cap_unchanged_skip_and_cmd_auth_clean_error(self) -> None:
        t_key = self.store.add_captured_task(
            plan_mod.parse_quick_capture(
                "+ Very Long Focused Kernel Debugging Step ~45m", self.ref
            ),
            self.ref,
        )
        self.store.add_captured_event(
            plan_mod.parse_quick_capture(
                "@ Distributed Systems Architecture Lecture today 14:30-16:00", self.ref
            ),
            self.ref,
        )
        with (
            mock.patch.object(plan_mod, "is_mako_dnd_active", return_value=True),
            mock.patch.object(plan_mod, "show_osd"),
        ):
            plan_mod.focus_start(self.store, t_key, self.ref)

        self.cfg.lock_status_path.unlink(missing_ok=True)
        with mock.patch.object(plan_mod, "atomic_write", wraps=plan_mod.atomic_write) as aw_spy:
            line1 = plan_mod.write_lock_status(self.store, self.ref)
            line2 = plan_mod.write_lock_status(self.store, self.ref)
            self.assertEqual(line1, line2)
            self.assertEqual(aw_spy.call_count, 1)
        unescaped = html.unescape(line1)
        self.assertIn("󰓾", unescaped)
        self.assertIn("󰃭", unescaped)
        self.assertIn("󰝖", unescaped)
        self.assertLessEqual(len(unescaped), 62)

        # cmd_auth handles unreachable server cleanly without traceback and returns exit code 1
        bad_cfg = plan_mod.PlanConfig(
            vikunja_url="http://127.0.0.1:1",
            vikunja_token="tk_bad",
            config_dir=self.cfg.config_dir,
            data_dir=self.cfg.data_dir,
            runtime_dir=self.cfg.runtime_dir,
        )
        args = plan_mod.build_parser().parse_args(
            ["auth", "--vikunja-token", "tk_bad", "--radicale-user", "julian", "--radicale-password", ""]
        )
        err_buf = io.StringIO()
        with (
            mock.patch.object(plan_mod, "load_config", return_value=bad_cfg),
            mock.patch("sys.stdout", io.StringIO()),
            mock.patch("sys.stderr", err_buf),
        ):
            rc = plan_mod.cmd_auth(self.cfg, args)
        self.assertEqual(rc, 1)
        self.assertIn("Vikunja unreachable", err_buf.getvalue())
        self.assertNotIn("Traceback", err_buf.getvalue())

    def test_remote_completion_releases_focus_overnight_span_and_daemon_reloads_creds(self) -> None:
        # 1. Overnight event span renders 20:00-24:00 on day 1 and 00:00-02:00 on day 2
        self.store.add_captured_event(
            plan_mod.parse_quick_capture("@ Night Hackathon today 20:00-02:00", self.ref),
            self.ref,
        )
        day_fri = plan_mod.compute_day_plan(self.store, self.ref)
        day_sat = plan_mod.compute_day_plan(
            self.store, self.ref + dt.timedelta(days=1)
        )
        self.assertEqual(
            plan_mod._format_block_span(day_fri.appointments[0], day_fri.date, sep="-"),
            "20:00-24:00",
        )
        self.assertEqual(
            plan_mod._format_block_span(day_sat.appointments[0], day_sat.date, sep="-"),
            "00:00-02:00",
        )

        # 2. Remote completion on another device releases active local Focus + owned DND
        mock_state = MockSyncState()
        mock_state.tasks[1] = {
            "id": 1,
            "project_id": 1,
            "title": "Remote Focus Task",
            "description": "",
            "done": False,
            "priority": 2,
            "due_date": "0001-01-01T00:00:00Z",
            "start_date": "0001-01-01T00:00:00Z",
            "end_date": "0001-01-01T00:00:00Z",
            "updated": "2026-11-20T12:00:00Z",
        }

        class BoundHandler(MockPlannerHandler):
            state = mock_state

        server = ThreadingHTTPServer(("127.0.0.1", 0), BoundHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)

        base_url = f"http://127.0.0.1:{server.server_port}"
        self.cfg.vikunja_url = base_url
        self.cfg.vikunja_token = "tk_live"
        plan_mod.sync_all(self.store, self.ref)

        dnd_calls: list[bool] = []
        with (
            mock.patch.object(plan_mod, "is_mako_dnd_active", return_value=False),
            mock.patch.object(plan_mod, "set_mako_dnd", side_effect=dnd_calls.append),
            mock.patch.object(plan_mod, "show_osd"),
        ):
            plan_mod.focus_start(self.store, "vk-1", self.ref)
            self.assertEqual(self.store.get_focus()["active"], 1)
            dnd_calls.clear()
            mock_state.tasks[1]["done"] = True
            plan_mod.sync_all(self.store, self.ref + dt.timedelta(minutes=2))
            self.assertEqual(self.store.get_focus()["active"], 0)
            self.assertIn(False, dnd_calls)

        # 3. run_daemon reloads load_config() and syncs immediately once credentials appear
        cfg_no_creds = plan_mod.PlanConfig(
            vikunja_url=base_url,
            vikunja_token="",
            sync_interval_sec=3600,
            config_dir=self.cfg.config_dir,
            data_dir=self.cfg.data_dir,
            runtime_dir=self.cfg.runtime_dir,
        )
        cfg_with_creds = plan_mod.PlanConfig(
            vikunja_url=base_url,
            vikunja_token="tk_live",
            sync_interval_sec=3600,
            config_dir=self.cfg.config_dir,
            data_dir=self.cfg.data_dir,
            runtime_dir=self.cfg.runtime_dir,
        )
        sync_tokens_seen: list[str] = []
        configs = [cfg_no_creds, cfg_with_creds]
        it = {"n": 0}

        class FakeEvent:
            def is_set(self) -> bool:
                return it["n"] >= 2

            def set(self) -> None:
                it["n"] = 2

            def wait(self, _timeout: float) -> bool:
                it["n"] += 1
                return it["n"] >= 2

        with (
            mock.patch.object(plan_mod.threading, "Event", return_value=FakeEvent()),
            mock.patch.object(plan_mod.signal, "signal"),
            mock.patch.object(plan_mod, "load_config", side_effect=lambda: configs[it["n"]]),
            mock.patch.object(
                plan_mod,
                "sync_all",
                side_effect=lambda st, _now: sync_tokens_seen.append(st.cfg.vikunja_token) or {"errors": []},
            ),
            mock.patch.object(plan_mod, "daemon_tick", return_value=[]),
        ):
            plan_mod.run_daemon(cfg_no_creds)

        # Both tick 0 (initial startup) AND tick 1 (immediately upon new token, despite 3600s interval!) synced!
        self.assertEqual(sync_tokens_seen, ["", "tk_live"])


if __name__ == "__main__":
    unittest.main()
