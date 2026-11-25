#!/usr/bin/env python3
"""Barless Hyprland Day Engine: offline-first Vikunja + Radicale planner, Rofi hub, Focus DND, and Mako daemon."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import fcntl
import getpass
import html
import json
import os
import re
import shutil
import signal
import sqlite3
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

ZERO_GO_PREFIXES = ("0001-", "0000-", "1970-01-01T00:00:00")
META_TAG_RE = re.compile(r"<!--\s*junix-plan:(\{.*?\})\s*-->", re.DOTALL)
EMPTY_HTML_P_RE = re.compile(r"<p>\s*</p>", re.IGNORECASE)
WEEKDAY_FULL_MAP = {
    "mon": 0,
    "monday": 0,
    "montag": 0,
    "tue": 1,
    "tues": 1,
    "tuesday": 1,
    "dienstag": 1,
    "wed": 2,
    "wednesday": 2,
    "mittwoch": 2,
    "thu": 3,
    "thur": 3,
    "thurs": 3,
    "thursday": 3,
    "donnerstag": 3,
    "fri": 4,
    "friday": 4,
    "freitag": 4,
    "sat": 5,
    "saturday": 5,
    "samstag": 5,
    "sun": 6,
    "sunday": 6,
    "sonntag": 6,
}
WEEKDAY_SHORT_MAP = {
    "mo": 0,
    "tu": 1,
    "di": 1,
    "we": 2,
    "mi": 2,
    "th": 3,
    "do": 3,
    "fr": 4,
    "sa": 5,
    "su": 6,
    "so": 6,
}
WEEKDAY_MAP = {**WEEKDAY_FULL_MAP, **WEEKDAY_SHORT_MAP}
RRULE_DAY_MAP = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}
PRIORITY_ALIASES = {
    "low": 1,
    "l": 1,
    "med": 2,
    "medium": 2,
    "m": 2,
    "high": 3,
    "h": 3,
    "urgent": 4,
    "u": 4,
    "crit": 5,
    "critical": 5,
}
GERMAN_WEEKDAYS = ("Mo", "Di", "Mi", "Do", "Fr", "Sa", "So")
GERMAN_MONTHS = (
    "",
    "Jan",
    "Feb",
    "Mär",
    "Apr",
    "Mai",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Okt",
    "Nov",
    "Dez",
)


# ============================================================================
# Configuration & Time Helpers
# ============================================================================


def _default_runtime_dir() -> Path:
    env_dir = os.environ.get("JUNIX_PLAN_RUNTIME_DIR") or os.environ.get("XDG_RUNTIME_DIR")
    if env_dir:
        return Path(env_dir)
    run_user = Path(f"/run/user/{os.getuid()}")
    return run_user if run_user.is_dir() else Path(f"/tmp/junix-plan-{os.getuid()}")


@dataclass
class PlanConfig:
    vikunja_url: str = "https://tasks.junixsrv.internal"
    radicale_url: str = "https://cal.junixsrv.internal"
    calendar_path: str = ""
    ca_cert: str = ""
    default_project: str = "Inbox"
    timezone: str = "Europe/Berlin"
    day_start_hour: int = 8
    day_end_hour: int = 22
    buffer_minutes: int = 5
    default_estimate_minutes: int = 25
    sync_interval_sec: int = 180
    auto_dnd: bool = True
    credentials_file: str = ""
    vikunja_token: str = ""
    radicale_user: str = ""
    radicale_password: str = ""
    config_dir: Path = field(default_factory=lambda: Path.home() / ".config/junix-plan")
    data_dir: Path = field(
        default_factory=lambda: Path.home() / ".local/share/junix-plan"
    )
    runtime_dir: Path = field(default_factory=_default_runtime_dir)

    @property
    def tz(self) -> ZoneInfo:
        try:
            return ZoneInfo(self.timezone)
        except Exception:
            return ZoneInfo("UTC")

    @property
    def db_path(self) -> Path:
        return self.data_dir / "state.db"

    @property
    def lock_status_path(self) -> Path:
        return self.runtime_dir / "junix-plan-lock.txt"

    @property
    def has_vikunja_creds(self) -> bool:
        return bool(self.vikunja_url and self.vikunja_token)

    @property
    def has_radicale_creds(self) -> bool:
        return bool(self.radicale_url and self.radicale_user and self.radicale_password)


def load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        val = val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
            val = val[1:-1]
        values[key.strip()] = val
    return values


def load_config() -> PlanConfig:
    xdg_cfg = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
    xdg_data = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local/share"))
    cfg_dir = Path(os.environ.get("JUNIX_PLAN_CONFIG_DIR") or (xdg_cfg / "junix-plan"))
    data_dir = Path(os.environ.get("JUNIX_PLAN_DATA_DIR") or (xdg_data / "junix-plan"))
    runtime_dir = _default_runtime_dir()

    cfg = PlanConfig(config_dir=cfg_dir, data_dir=data_dir, runtime_dir=runtime_dir)
    cfg_json = cfg_dir / "config.json"
    if cfg_json.is_file():
        try:
            raw = json.loads(cfg_json.read_text(encoding="utf-8"))
            for k in (
                "vikunja_url",
                "radicale_url",
                "calendar_path",
                "ca_cert",
                "default_project",
                "timezone",
                "day_start_hour",
                "day_end_hour",
                "buffer_minutes",
                "default_estimate_minutes",
                "sync_interval_sec",
                "auto_dnd",
                "credentials_file",
                "radicale_user",
            ):
                if k in raw and raw[k] is not None:
                    setattr(cfg, k, raw[k])
        except Exception as exc:
            print(f"warning: failed reading {cfg_json}: {exc}", file=sys.stderr)

    json_rad_user = cfg.radicale_user
    cred_candidates = [cfg_dir / "credentials.env"]
    if cfg.credentials_file:
        cred_candidates.append(Path(cfg.credentials_file))
    for cred_path in cred_candidates:
        env_vals = load_env_file(cred_path)
        if env_vals:
            cfg.vikunja_token = env_vals.get("VIKUNJA_TOKEN", cfg.vikunja_token)
            cfg.radicale_user = env_vals.get("RADICALE_USER", cfg.radicale_user)
            cfg.radicale_password = env_vals.get(
                "RADICALE_PASSWORD", cfg.radicale_password
            )
            if "VIKUNJA_URL" in env_vals:
                cfg.vikunja_url = env_vals["VIKUNJA_URL"]
            if "RADICALE_URL" in env_vals:
                cfg.radicale_url = env_vals["RADICALE_URL"]
            if "RADICALE_CALENDAR_PATH" in env_vals:
                cfg.calendar_path = env_vals["RADICALE_CALENDAR_PATH"]

    # Explicit environment overrides take highest precedence.
    cfg.vikunja_url = os.environ.get("VIKUNJA_URL", cfg.vikunja_url).rstrip("/")
    cfg.radicale_url = os.environ.get("RADICALE_URL", cfg.radicale_url).rstrip("/")
    cfg.vikunja_token = os.environ.get("VIKUNJA_TOKEN", cfg.vikunja_token)
    cfg.radicale_user = os.environ.get("RADICALE_USER", cfg.radicale_user)
    cfg.radicale_password = os.environ.get("RADICALE_PASSWORD", cfg.radicale_password)
    cfg.ca_cert = os.environ.get("JUNIX_PLAN_CA_CERT", cfg.ca_cert)
    if "RADICALE_CALENDAR_PATH" in os.environ:
        cfg.calendar_path = os.environ["RADICALE_CALENDAR_PATH"]
    elif (
        json_rad_user
        and cfg.radicale_user
        and cfg.radicale_user != json_rad_user
        and cfg.calendar_path.startswith(f"/{json_rad_user}/")
    ):
        tail_slug = cfg.calendar_path[len(f"/{json_rad_user}/") :]
        cfg.calendar_path = f"/{urllib.parse.quote(cfg.radicale_user)}/{tail_slug}"
    return cfg


def now_local(cfg: PlanConfig) -> dt.datetime:
    return dt.datetime.now(cfg.tz)


def to_utc_iso(value: dt.datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=dt.timezone.utc)
    return value.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def from_iso(value: str | None, tz: ZoneInfo) -> dt.datetime | None:
    if not value:
        return None
    for prefix in ZERO_GO_PREFIXES:
        if value.startswith(prefix):
            return None
    cleaned = value.strip()
    if cleaned.endswith("Z"):
        cleaned = cleaned[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(cleaned)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=tz)
    return parsed.astimezone(tz)


def atomic_write(path: Path, content: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            delete=False,
        ) as handle:
            tmp_path = Path(handle.name)
            handle.write(content)
            handle.flush()
            os.fchmod(handle.fileno(), mode)
        os.replace(tmp_path, path)
    finally:
        if tmp_path is not None:
            tmp_path.unlink(missing_ok=True)


def encode_task_description(
    clean_desc: str,
    estimate_min: int | None,
    step_index: int | None,
    auto_slotted: bool = False,
    auto_start: str | None = None,
    auto_end: str | None = None,
) -> str:
    meta: dict[str, Any] = {}
    if estimate_min and estimate_min > 0:
        meta["est"] = int(estimate_min)
    if step_index is not None and step_index > 0:
        meta["step"] = int(step_index)
    if auto_slotted:
        meta["auto"] = 1
        if auto_start:
            meta["auto_s"] = auto_start
        if auto_end:
            meta["auto_e"] = auto_end
    base = (clean_desc or "").strip()
    if not meta:
        return base
    tag = f"<!-- junix-plan:{json.dumps(meta, separators=(',', ':'))} -->"
    return f"{base}\n\n{tag}" if base else tag


def _decode_task_meta_window(
    raw_desc: str | None,
) -> tuple[str | None, str | None]:
    if not raw_desc:
        return None, None
    match = META_TAG_RE.search(raw_desc)
    if not match:
        return None, None
    try:
        meta = json.loads(match.group(1))
        s_val = str(meta["auto_s"]) if meta.get("auto_s") else None
        e_val = str(meta["auto_e"]) if meta.get("auto_e") else None
        return s_val, e_val
    except Exception:
        return None, None


def decode_task_description(
    raw_desc: str | None,
) -> tuple[str, int | None, int | None, bool]:
    if not raw_desc:
        return "", None, None, False
    match = META_TAG_RE.search(raw_desc)
    if not match:
        return raw_desc.strip(), None, None, False
    stripped = (raw_desc[: match.start()] + raw_desc[match.end() :]).strip()
    clean = EMPTY_HTML_P_RE.sub("", stripped).strip()
    try:
        meta = json.loads(match.group(1))
        est = int(meta["est"]) if "est" in meta else None
        step = int(meta["step"]) if "step" in meta else None
        auto = bool(meta.get("auto"))
        return clean, est, step, auto
    except Exception:
        return raw_desc.strip(), None, None, False


# ============================================================================
# Natural-Language Quick Capture Parser (Tasks, Steps, & Appointments)
# ============================================================================


@dataclass
class ParsedStep:
    title: str
    estimate_min: int | None = None


@dataclass
class ParsedCapture:
    kind: str  # "task" or "event"
    title: str
    project: str = "Inbox"
    priority: int = 0
    estimate_min: int | None = None
    due_at: dt.datetime | None = None
    start_at: dt.datetime | None = None
    end_at: dt.datetime | None = None
    all_day: bool = False
    location: str = ""
    rrule: str = ""
    steps: list[ParsedStep] = field(default_factory=list)


DURATION_TOKEN_RE = re.compile(
    r"^~?(?:(?P<h>\d+(?:\.\d+)?)h)?(?:(?P<m>\d+)m)?$", re.IGNORECASE
)
TIME_RANGE_RE = re.compile(
    r"^(?P<sh>\d{1,2}):(?P<sm>\d{2})-(?P<eh>\d{1,2}):(?P<em>\d{2})$"
)
TIME_SINGLE_RE = re.compile(r"^(?P<h>\d{1,2}):(?P<m>\d{2})$")
ISO_DATE_RE = re.compile(r"^(?P<y>\d{4})-(?P<m>\d{2})-(?P<d>\d{2})$")
DE_DATE_RE = re.compile(r"^(?P<d>\d{1,2})\.(?P<m>\d{1,2})\.(?P<y>\d{4})?$")


def parse_duration_token(token: str, require_tilde: bool = True) -> int | None:
    if require_tilde and not token.startswith("~"):
        return None
    body = token[1:] if token.startswith("~") else token
    if not body:
        return None
    m = DURATION_TOKEN_RE.match(body)
    if not m or (m.group("h") is None and m.group("m") is None):
        return None
    minutes = 0.0
    if m.group("h") is not None:
        minutes += float(m.group("h")) * 60.0
    if m.group("m") is not None:
        minutes += float(m.group("m"))
    res = int(round(minutes))
    return res if res > 0 else None


def _next_is_clock_token(tokens: list[str], idx: int) -> bool:
    if idx + 1 >= len(tokens):
        return False
    nxt = tokens[idx + 1]
    return bool(TIME_RANGE_RE.match(nxt) or TIME_SINGLE_RE.match(nxt))


def _is_meta_tail(tokens: list[str], start_idx: int, kind: str) -> bool:
    """Return True if all tokens from start_idx onward are scheduling/metadata modifiers (not prose)."""
    j = start_idx
    seen_clock = False
    while j < len(tokens):
        t = tokens[j]
        low = t.lower()
        if low == "in" and j + 1 < len(tokens) and parse_duration_token(tokens[j + 1], require_tilde=False) is not None:
            seen_clock = True
            j += 2
            continue
        if parse_duration_token(t, require_tilde=(kind == "task" or not seen_clock)) is not None:
            j += 1
            continue
        if t.startswith("!") and len(t) > 1:
            bangs = t.lstrip("!")
            if not bangs or (bangs.isdigit() and 1 <= int(bangs) <= 5) or bangs.lower() in PRIORITY_ALIASES:
                j += 1
                continue
        if t.startswith("#") and len(t) > 1:
            j += 1
            continue
        if kind == "event" and t.startswith("@") and len(t) > 1:
            j += 1
            continue
        if kind == "event" and low in ("daily", "weekly", "biweekly", "monthly", "yearly"):
            j += 1
            continue
        if TIME_RANGE_RE.match(t) or TIME_SINGLE_RE.match(t):
            seen_clock = True
            j += 1
            continue
        return False
    return True


def _resolve_weekday(base_date: dt.date, target_wd: int) -> dt.date:
    delta = (target_wd - base_date.weekday()) % 7
    if delta == 0:
        delta = 7
    return base_date + dt.timedelta(days=delta)


def parse_step_segment(raw: str) -> ParsedStep:
    words: list[str] = []
    est: int | None = None
    for tok in raw.strip().split():
        dur = parse_duration_token(tok, require_tilde=True)
        if dur is not None:
            est = dur
        else:
            words.append(tok)
    return ParsedStep(title=" ".join(words).strip(), estimate_min=est)


def parse_quick_capture(
    text: str,
    ref: dt.datetime,
    default_kind: str = "task",
    default_project: str = "Inbox",
    default_estimate_minutes: int = 25,
) -> ParsedCapture:
    raw = text.strip()
    kind = default_kind
    if raw.startswith("+"):
        kind = "task"
        raw = raw[1:].strip()
    elif raw.startswith("@"):
        kind = "event"
        raw = raw[1:].strip()

    step_parts = [seg.strip() for seg in raw.split(">>")] if ">>" in raw else [raw]
    head = step_parts[0]
    parsed_steps = [
        ps for ps in (parse_step_segment(seg) for seg in step_parts[1:]) if ps.title
    ]

    tokens = head.split()
    title_words: list[str] = []
    project = default_project or "Inbox"
    priority = 0
    estimate_min: int | None = None
    chosen_date: dt.date | None = None
    start_clock: tuple[int, int] | None = None
    end_clock: tuple[int, int] | None = None
    rel_delta: dt.timedelta | None = None
    location = ""
    rrule = ""

    i = 0
    while i < len(tokens):
        tok = tokens[i]
        low = tok.lower()

        # Relative "in 30m" / "in 2h"
        if low == "in" and i + 1 < len(tokens):
            rel_min = parse_duration_token(tokens[i + 1], require_tilde=False)
            if rel_min is not None:
                rel_delta = dt.timedelta(minutes=rel_min)
                i += 2
                continue

        # Duration estimate "~45m", "~1.5h" (or trailing bare "90m" after an event clock/relative time)
        dur = parse_duration_token(
            tok,
            require_tilde=(kind == "task" or (start_clock is None and rel_delta is None)),
        )
        if dur is not None:
            estimate_min = dur
            i += 1
            continue

        # Priority "!1".."!5", "!high", "!!!"
        if tok.startswith("!") and len(tok) > 1:
            bangs = tok.lstrip("!")
            if not bangs:
                priority = min(5, len(tok))
                i += 1
                continue
            if bangs.isdigit() and 1 <= int(bangs) <= 5:
                priority = int(bangs)
                i += 1
                continue
            if bangs.lower() in PRIORITY_ALIASES:
                priority = PRIORITY_ALIASES[bangs.lower()]
                i += 1
                continue

        # Project "#uni"
        if tok.startswith("#") and len(tok) > 1:
            project = tok[1:]
            i += 1
            continue

        # Event location "@Room-101"
        if kind == "event" and tok.startswith("@") and len(tok) > 1:
            location = tok[1:].replace("_", " ")
            i += 1
            continue

        # Event recurrence keywords (only after at least one title word so "@ Weekly Seminar ... weekly" keeps "Weekly Seminar")
        if (
            kind == "event"
            and title_words
            and low in ("daily", "weekly", "biweekly", "monthly", "yearly")
        ):
            if low == "biweekly":
                rrule = "FREQ=WEEKLY;INTERVAL=2"
            else:
                rrule = f"FREQ={low.upper()}"
            i += 1
            continue

        # Date keywords (only after at least one title word and when followed solely by metadata,
        # preventing prose words like "+ Do laundry", "+ We need to go", "+ Check Sat receiver ~20m",
        # or "+ Section 1.2. notes" from being eaten as dates!)
        in_date_zone = bool(title_words) and _is_meta_tail(tokens, i + 1, kind)
        has_date_prep = bool(title_words and title_words[-1].lower() in ("am", "on"))

        if in_date_zone and low in ("today", "heute"):
            if has_date_prep:
                title_words.pop()
            chosen_date = ref.date()
            i += 1
            continue
        if in_date_zone and low in ("tomorrow", "tmr", "morgen"):
            if has_date_prep:
                title_words.pop()
            chosen_date = ref.date() + dt.timedelta(days=1)
            i += 1
            continue
        if in_date_zone and low == "übermorgen":
            if has_date_prep:
                title_words.pop()
            chosen_date = ref.date() + dt.timedelta(days=2)
            i += 1
            continue
        if in_date_zone and low in WEEKDAY_FULL_MAP:
            if has_date_prep:
                title_words.pop()
            chosen_date = _resolve_weekday(ref.date(), WEEKDAY_FULL_MAP[low])
            i += 1
            continue
        if in_date_zone and low in WEEKDAY_SHORT_MAP:
            # 2-letter codes ("do", "we", "so", "sa", ...) collide with common words unless anchored
            # by a clock ("Do 14:00"), preposition ("am Do" / "on Fr"), or capitalized non-English code ("Fr", "Di", "Mi", "Mo", "Sa")
            if (
                _next_is_clock_token(tokens, i)
                or has_date_prep
                or (low not in ("do", "we", "so", "tu", "th", "su") and tok[0].isupper())
            ):
                if has_date_prep:
                    title_words.pop()
                chosen_date = _resolve_weekday(ref.date(), WEEKDAY_SHORT_MAP[low])
                i += 1
                continue

        m_iso = ISO_DATE_RE.match(tok)
        if m_iso:
            try:
                chosen_date = dt.date(
                    int(m_iso.group("y")), int(m_iso.group("m")), int(m_iso.group("d"))
                )
                if has_date_prep:
                    title_words.pop()
                i += 1
                continue
            except ValueError:
                pass

        m_de = DE_DATE_RE.match(tok)
        if m_de:
            yr_raw = m_de.group("y")
            has_two_digit_part = len(m_de.group("d")) == 2 or len(m_de.group("m")) == 2
            if yr_raw or (
                in_date_zone
                and (_next_is_clock_token(tokens, i) or has_two_digit_part or has_date_prep)
            ):
                try:
                    yr = ref.year if not yr_raw else int(yr_raw)
                    candidate = dt.date(yr, int(m_de.group("m")), int(m_de.group("d")))
                    if not yr_raw and candidate < ref.date():
                        candidate = dt.date(yr + 1, candidate.month, candidate.day)
                    if has_date_prep:
                        title_words.pop()
                    chosen_date = candidate
                    i += 1
                    continue
                except ValueError:
                    pass

        # Time range "14:00-15:30"
        m_rng = TIME_RANGE_RE.match(tok)
        if m_rng:
            sh, sm = int(m_rng.group("sh")), int(m_rng.group("sm"))
            eh, em = int(m_rng.group("eh")), int(m_rng.group("em"))
            if 0 <= sh <= 23 and 0 <= sm <= 59 and 0 <= eh <= 23 and 0 <= em <= 59:
                start_clock = (sh, sm)
                end_clock = (eh, em)
                i += 1
                continue

        # Single clock "14:30"
        m_clk = TIME_SINGLE_RE.match(tok)
        if m_clk:
            hh, mm = int(m_clk.group("h")), int(m_clk.group("m"))
            if 0 <= hh <= 23 and 0 <= mm <= 59:
                start_clock = (hh, mm)
                i += 1
                continue

        title_words.append(tok)
        i += 1

    title = " ".join(title_words).strip() or "Untitled"
    tz = ref.tzinfo or ZoneInfo("UTC")

    due_at: dt.datetime | None = None
    start_at: dt.datetime | None = None
    end_at: dt.datetime | None = None
    all_day = False

    if rel_delta is not None:
        target_dt = (ref + rel_delta).replace(second=0, microsecond=0)
        if kind == "event":
            start_at = target_dt
            end_at = target_dt + dt.timedelta(minutes=estimate_min or 60)
        else:
            due_at = target_dt
    elif chosen_date is not None or start_clock is not None:
        base_d = chosen_date or ref.date()
        if start_clock is not None and chosen_date is None:
            candidate_dt = dt.datetime(
                base_d.year, base_d.month, base_d.day, start_clock[0], start_clock[1], tzinfo=tz
            )
            if candidate_dt < ref - dt.timedelta(minutes=5):
                base_d = base_d + dt.timedelta(days=1)

        if kind == "event":
            if start_clock is not None:
                start_at = dt.datetime(
                    base_d.year, base_d.month, base_d.day, start_clock[0], start_clock[1], tzinfo=tz
                )
                if end_clock is not None:
                    end_at = dt.datetime(
                        base_d.year, base_d.month, base_d.day, end_clock[0], end_clock[1], tzinfo=tz
                    )
                    if end_at <= start_at:
                        end_at += dt.timedelta(days=1)
                else:
                    end_at = start_at + dt.timedelta(minutes=estimate_min or 60)
            else:
                all_day = True
                start_at = dt.datetime(base_d.year, base_d.month, base_d.day, 0, 0, tzinfo=tz)
                end_at = start_at + dt.timedelta(days=1)
        else:
            if end_clock is not None and start_clock is not None:
                start_at = dt.datetime(
                    base_d.year, base_d.month, base_d.day, start_clock[0], start_clock[1], tzinfo=tz
                )
                end_at = dt.datetime(
                    base_d.year, base_d.month, base_d.day, end_clock[0], end_clock[1], tzinfo=tz
                )
                if end_at <= start_at:
                    end_at += dt.timedelta(days=1)
                due_at = end_at
                if estimate_min is None:
                    estimate_min = int((end_at - start_at).total_seconds() // 60)
            elif start_clock is not None:
                due_at = dt.datetime(
                    base_d.year, base_d.month, base_d.day, start_clock[0], start_clock[1], tzinfo=tz
                )
            else:
                due_at = dt.datetime(base_d.year, base_d.month, base_d.day, 18, 0, tzinfo=tz)
    elif kind == "event":
        start_at = (ref + dt.timedelta(hours=1)).replace(minute=0, second=0, microsecond=0)
        end_at = start_at + dt.timedelta(minutes=estimate_min or 60)

    if parsed_steps and estimate_min is None:
        step_total = sum(
            s.estimate_min or default_estimate_minutes for s in parsed_steps
        )
        estimate_min = step_total

    return ParsedCapture(
        kind=kind,
        title=title,
        project=project,
        priority=priority,
        estimate_min=estimate_min,
        due_at=due_at,
        start_at=start_at,
        end_at=end_at,
        all_day=all_day,
        location=location,
        rrule=rrule,
        steps=parsed_steps,
    )


# ============================================================================
# RFC 5545 iCalendar Parser, RRULE Day Expander, & Serializer
# ============================================================================


def unfold_ics(raw: str) -> list[str]:
    lines: list[str] = []
    for line in raw.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if line.startswith((" ", "\t")) and lines:
            lines[-1] += line[1:]
        else:
            lines.append(line)
    return lines


ICS_UNESCAPE_RE = re.compile(r"\\([nN,;\\])")


def _unescape_ics_text(val: str) -> str:
    return ICS_UNESCAPE_RE.sub(
        lambda m: "\n" if m.group(1) in ("n", "N") else m.group(1),
        val,
    )


def _escape_ics_text(val: str) -> str:
    return (
        val.replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\n", "\\n")
    )


def parse_ics_datetime(val: str, params: dict[str, str], default_tz: ZoneInfo) -> tuple[dt.datetime, bool]:
    val = val.strip()
    if params.get("VALUE", "").upper() == "DATE" or len(val) == 8:
        d = dt.date(int(val[0:4]), int(val[4:6]), int(val[6:8]))
        return dt.datetime(d.year, d.month, d.day, 0, 0, tzinfo=default_tz), True
    tz = default_tz
    if "TZID" in params:
        try:
            tz = ZoneInfo(params["TZID"])
        except Exception:
            tz = default_tz
    if val.endswith("Z"):
        d_utc = dt.datetime.strptime(val, "%Y%m%dT%H%M%SZ").replace(tzinfo=dt.timezone.utc)
        return d_utc.astimezone(default_tz), False
    d_loc = dt.datetime.strptime(val[:15], "%Y%m%dT%H%M%S").replace(tzinfo=tz)
    return d_loc.astimezone(default_tz), False


def parse_ics_duration(val: str) -> dt.timedelta:
    m = re.match(
        r"^(?P<sign>-)?P(?:(?P<w>\d+)W)?(?:(?P<d>\d+)D)?(?:T(?:(?P<h>\d+)H)?(?:(?P<m>\d+)M)?(?:(?P<s>\d+)S)?)?$",
        val.strip().upper(),
    )
    if not m:
        return dt.timedelta(hours=1)
    delta = dt.timedelta(
        weeks=int(m.group("w") or 0),
        days=int(m.group("d") or 0),
        hours=int(m.group("h") or 0),
        minutes=int(m.group("m") or 0),
        seconds=int(m.group("s") or 0),
    )
    return -delta if m.group("sign") else delta


@dataclass
class IcsEvent:
    uid: str
    summary: str
    dtstart: dt.datetime
    dtend: dt.datetime
    all_day: bool = False
    location: str = ""
    description: str = ""
    rrule: str = ""
    exdates: set[dt.date] = field(default_factory=set)
    raw_ics: str = ""


def _split_ics_property(line: str) -> tuple[str, dict[str, str], str] | None:
    """Split an RFC 5545 content line on ':' and ';' outside double-quoted parameter values."""
    in_quotes = False
    colon_idx = -1
    for idx, ch in enumerate(line):
        if ch == '"':
            in_quotes = not in_quotes
        elif ch == ":" and not in_quotes:
            colon_idx = idx
            break
    if colon_idx < 0:
        return None
    left, value = line[:colon_idx], line[colon_idx + 1 :]
    parts: list[str] = []
    buf: list[str] = []
    in_quotes = False
    for ch in left:
        if ch == '"':
            in_quotes = not in_quotes
            buf.append(ch)
        elif ch == ";" and not in_quotes:
            parts.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    parts.append("".join(buf))
    name = parts[0].strip().upper()
    if not name:
        return None
    params: dict[str, str] = {}
    for p in parts[1:]:
        if "=" in p:
            pk, pv = p.split("=", 1)
            pv_clean = pv.strip()
            if len(pv_clean) >= 2 and pv_clean[0] == '"' and pv_clean[-1] == '"':
                pv_clean = pv_clean[1:-1]
            params[pk.strip().upper()] = pv_clean
    return name, params, value


def parse_ics_events(raw_ics: str, default_tz: ZoneInfo) -> list[IcsEvent]:
    events: list[IcsEvent] = []
    override_exdates: dict[str, set[dt.date]] = {}
    in_vevent = False
    subcomponent_depth = 0
    props: list[tuple[str, dict[str, str], str]] = []

    for line in unfold_ics(raw_ics):
        stripped = line.strip()
        upper = stripped.upper()
        if not in_vevent:
            if upper == "BEGIN:VEVENT":
                in_vevent = True
                subcomponent_depth = 0
                props = []
            continue
        if upper.startswith("BEGIN:"):
            subcomponent_depth += 1
            continue
        if upper == "END:VEVENT" and subcomponent_depth == 0:
            in_vevent = False
            ev, base_uid, rec_date = _build_ics_event(props, default_tz, raw_ics)
            if base_uid and rec_date is not None:
                override_exdates.setdefault(base_uid, set()).add(rec_date)
            if ev is not None:
                events.append(ev)
            continue
        if upper.startswith("END:") and subcomponent_depth > 0:
            subcomponent_depth -= 1
            continue
        if subcomponent_depth == 0:
            parsed_prop = _split_ics_property(line)
            if parsed_prop is not None:
                props.append(parsed_prop)

    for ev in events:
        if ev.uid in override_exdates:
            ev.exdates |= override_exdates[ev.uid]
    return events


def _build_ics_event(
    props: list[tuple[str, dict[str, str], str]], default_tz: ZoneInfo, raw_ics: str
) -> tuple[IcsEvent | None, str, dt.date | None]:
    uid = ""
    summary = "Untitled Event"
    location = ""
    description = ""
    rrule = ""
    status = ""
    dtstart: dt.datetime | None = None
    dtend: dt.datetime | None = None
    duration: dt.timedelta | None = None
    all_day = False
    recurrence_dt: dt.datetime | None = None
    has_recurrence_id = False
    exdates: set[dt.date] = set()

    for name, params, val in props:
        if name == "UID":
            uid = val.strip()
        elif name == "STATUS":
            status = val.strip().upper()
        elif name == "RECURRENCE-ID":
            has_recurrence_id = True
            try:
                recurrence_dt, _ = parse_ics_datetime(val, params, default_tz)
            except Exception:
                recurrence_dt = None
        elif name == "SUMMARY":
            summary = _unescape_ics_text(val.strip()) or "Untitled Event"
        elif name == "LOCATION":
            location = _unescape_ics_text(val.strip())
        elif name == "DESCRIPTION":
            description = _unescape_ics_text(val.strip())
        elif name == "RRULE":
            rrule = val.strip()
        elif name == "DTSTART":
            try:
                dtstart, all_day = parse_ics_datetime(val, params, default_tz)
            except Exception:
                return None, uid, None
        elif name == "DTEND":
            try:
                dtend, _ = parse_ics_datetime(val, params, default_tz)
            except Exception:
                dtend = None
        elif name == "DURATION":
            duration = parse_ics_duration(val)
        elif name == "EXDATE":
            for chunk in val.split(","):
                chunk = chunk.strip()
                if chunk:
                    try:
                        ex_dt, _ = parse_ics_datetime(chunk, params, default_tz)
                        exdates.add(ex_dt.date())
                    except Exception:
                        pass

    rec_date = (
        recurrence_dt.date()
        if recurrence_dt is not None
        else (dtstart.date() if (has_recurrence_id and dtstart is not None) else None)
    )
    if status == "CANCELLED":
        return None, uid, rec_date
    if dtstart is None:
        return None, uid, rec_date
    base_uid = uid
    if has_recurrence_id and uid:
        tag = recurrence_dt.strftime("%Y%m%dT%H%M") if recurrence_dt else dtstart.strftime("%Y%m%dT%H%M")
        uid = f"{uid}#override-{tag}"
    if not uid:
        uid = str(uuid.uuid4())
    if dtend is None:
        if duration is not None:
            dtend = dtstart + duration
        elif all_day:
            dtend = dtstart + dt.timedelta(days=1)
        else:
            dtend = dtstart + dt.timedelta(hours=1)
    return (
        IcsEvent(
            uid=uid,
            summary=summary,
            dtstart=dtstart,
            dtend=dtend,
            all_day=all_day,
            location=location,
            description=description,
            rrule=rrule,
            exdates=exdates,
            raw_ics=raw_ics,
        ),
        base_uid,
        rec_date,
    )


def build_ics_document(
    uid: str,
    summary: str,
    dtstart: dt.datetime,
    dtend: dt.datetime,
    tz_name: str,
    all_day: bool = False,
    location: str = "",
    description: str = "",
    rrule: str = "",
    exdates: set[dt.date] | list[dt.date] | None = None,
) -> str:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Junix//Day Engine//EN",
        "BEGIN:VEVENT",
        f"UID:{uid}",
        f"DTSTAMP:{stamp}",
    ]
    local_tz = ZoneInfo(tz_name)
    s_loc = dtstart.astimezone(local_tz)
    e_loc = dtend.astimezone(local_tz)
    if all_day:
        lines.append(f"DTSTART;VALUE=DATE:{dtstart.strftime('%Y%m%d')}")
        lines.append(f"DTEND;VALUE=DATE:{dtend.strftime('%Y%m%d')}")
    else:
        lines.append(f"DTSTART;TZID={tz_name}:{s_loc.strftime('%Y%m%dT%H%M%S')}")
        lines.append(f"DTEND;TZID={tz_name}:{e_loc.strftime('%Y%m%dT%H%M%S')}")
    lines.append(f"SUMMARY:{_escape_ics_text(summary)}")
    if location:
        lines.append(f"LOCATION:{_escape_ics_text(location)}")
    if description:
        lines.append(f"DESCRIPTION:{_escape_ics_text(description)}")
    if rrule:
        lines.append(f"RRULE:{rrule}")
    if exdates:
        sorted_ex = sorted(set(exdates))
        if all_day:
            ex_vals = ",".join(d.strftime("%Y%m%d") for d in sorted_ex)
            lines.append(f"EXDATE;VALUE=DATE:{ex_vals}")
        else:
            clock_sfx = s_loc.strftime("%H%M%S")
            ex_vals = ",".join(f"{d.strftime('%Y%m%d')}T{clock_sfx}" for d in sorted_ex)
            lines.append(f"EXDATE;TZID={tz_name}:{ex_vals}")
    lines.extend(["END:VEVENT", "END:VCALENDAR", ""])
    return "\r\n".join(lines)


def _rrule_occurrence_on_start_date(
    ev: IcsEvent,
    start_local: dt.datetime,
    candidate_date: dt.date,
    parts: dict[str, str],
    until_dt: dt.datetime | None,
    until_is_date: bool,
    tz: ZoneInfo,
) -> dt.datetime | None:
    if candidate_date < start_local.date() or candidate_date in ev.exdates:
        return None
    if until_dt is not None and candidate_date > until_dt.date():
        return None

    freq = parts.get("FREQ", "")
    interval = max(1, int(parts.get("INTERVAL", "1") or "1"))
    count_limit = int(parts["COUNT"]) if "COUNT" in parts and parts["COUNT"].isdigit() else None
    byday_tokens = [
        tok[-2:] for tok in parts.get("BYDAY", "").split(",") if len(tok) >= 2 and tok[-2:] in RRULE_DAY_MAP
    ]

    matched = False
    if freq == "DAILY":
        days_diff = (candidate_date - start_local.date()).days
        if days_diff % interval == 0:
            if not byday_tokens or candidate_date.weekday() in [RRULE_DAY_MAP[d] for d in byday_tokens]:
                if count_limit is None or (days_diff // interval) < count_limit:
                    matched = True
    elif freq == "WEEKLY":
        allowed_wds = (
            [RRULE_DAY_MAP[d] for d in byday_tokens]
            if byday_tokens
            else [start_local.weekday()]
        )
        start_week_monday = start_local.date() - dt.timedelta(days=start_local.weekday())
        target_week_monday = candidate_date - dt.timedelta(days=candidate_date.weekday())
        weeks_diff = (target_week_monday - start_week_monday).days // 7
        if weeks_diff >= 0 and weeks_diff % interval == 0 and candidate_date.weekday() in allowed_wds:
            if count_limit is not None:
                occ = 0
                cur = start_local.date()
                while cur <= candidate_date and occ <= count_limit:
                    w = ((cur - dt.timedelta(days=cur.weekday())) - start_week_monday).days // 7
                    if w % interval == 0 and cur.weekday() in allowed_wds:
                        occ += 1
                    cur += dt.timedelta(days=1)
                matched = occ <= count_limit
            else:
                matched = True
    elif freq == "MONTHLY":
        months_diff = (candidate_date.year - start_local.year) * 12 + (
            candidate_date.month - start_local.month
        )
        if months_diff >= 0 and months_diff % interval == 0 and candidate_date.day == start_local.day:
            if count_limit is None or (months_diff // interval) < count_limit:
                matched = True
    elif freq == "YEARLY":
        years_diff = candidate_date.year - start_local.year
        if (
            years_diff >= 0
            and years_diff % interval == 0
            and (candidate_date.month, candidate_date.day) == (start_local.month, start_local.day)
        ):
            if count_limit is None or (years_diff // interval) < count_limit:
                matched = True

    if not matched:
        return None

    occ_start = dt.datetime(
        candidate_date.year,
        candidate_date.month,
        candidate_date.day,
        start_local.hour,
        start_local.minute,
        start_local.second,
        tzinfo=tz,
    )
    if until_dt is not None and not until_is_date and occ_start > until_dt:
        return None
    return occ_start


def expand_event_on_date(
    ev: IcsEvent, target_date: dt.date, tz: ZoneInfo
) -> list[tuple[dt.datetime, dt.datetime]]:
    start_local = ev.dtstart.astimezone(tz)
    end_local = ev.dtend.astimezone(tz)
    duration = max(dt.timedelta(minutes=5), end_local - start_local)
    day_begin = dt.datetime(target_date.year, target_date.month, target_date.day, 0, 0, tzinfo=tz)
    day_end = day_begin + dt.timedelta(days=1)

    if not ev.rrule:
        if start_local < day_end and end_local > day_begin:
            return [(start_local, end_local)]
        return []

    parts: dict[str, str] = {}
    for kv in ev.rrule.split(";"):
        if "=" in kv:
            k, v = kv.split("=", 1)
            parts[k.upper()] = v.upper()

    until_dt: dt.datetime | None = None
    until_is_date = False
    if "UNTIL" in parts:
        try:
            until_dt, until_is_date = parse_ics_datetime(parts["UNTIL"], {}, tz)
        except Exception:
            until_dt = None

    # Check prior start dates as well when a timed recurring event spans across midnight
    max_lookback_days = 0
    if not ev.all_day:
        end_offset_sec = (
            start_local.hour * 3600
            + start_local.minute * 60
            + start_local.second
            + duration.total_seconds()
        )
        if end_offset_sec > 86400:
            max_lookback_days = min(7, int((end_offset_sec - 1) // 86400))

    matches: list[tuple[dt.datetime, dt.datetime]] = []
    for back in range(max_lookback_days, -1, -1):
        cand_date = target_date - dt.timedelta(days=back)
        occ_start = _rrule_occurrence_on_start_date(
            ev, start_local, cand_date, parts, until_dt, until_is_date, tz
        )
        if occ_start is not None:
            occ_end = occ_start + duration
            if occ_start < day_end and occ_end > day_begin:
                matches.append((occ_start, occ_end))
    return matches


# ============================================================================
# Local Offline-First SQLite Store
# ============================================================================


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS projects (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tasks (
  local_key TEXT PRIMARY KEY,
  remote_id INTEGER UNIQUE,
  parent_key TEXT,
  step_index INTEGER,
  project_id INTEGER,
  project_name TEXT NOT NULL DEFAULT 'Inbox',
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  priority INTEGER NOT NULL DEFAULT 0,
  estimate_min INTEGER,
  due_at TEXT,
  start_at TEXT,
  end_at TEXT,
  auto_slotted INTEGER NOT NULL DEFAULT 0,
  done INTEGER NOT NULL DEFAULT 0,
  snoozed_until TEXT,
  dirty_op TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS events (
  uid TEXT PRIMARY KEY,
  href TEXT,
  etag TEXT,
  summary TEXT NOT NULL,
  location TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  dtstart TEXT NOT NULL,
  dtend TEXT NOT NULL,
  all_day INTEGER NOT NULL DEFAULT 0,
  rrule TEXT NOT NULL DEFAULT '',
  exdates TEXT NOT NULL DEFAULT '',
  raw_ics TEXT NOT NULL DEFAULT '',
  dirty_op TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS focus (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  active INTEGER NOT NULL DEFAULT 0,
  task_key TEXT,
  title TEXT NOT NULL DEFAULT '',
  parent_title TEXT NOT NULL DEFAULT '',
  started_at TEXT,
  ends_at TEXT,
  duration_min INTEGER NOT NULL DEFAULT 25,
  dnd_owned INTEGER NOT NULL DEFAULT 0,
  completed_prompted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS notified (
  dedup_key TEXT PRIMARY KEY,
  fired_at TEXT NOT NULL
);
"""


class PlanStore:
    SCHEMA_VERSION = 1

    def __init__(self, cfg: PlanConfig):
        self.cfg = cfg
        cfg.data_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        is_new = not cfg.db_path.exists()
        self.conn = sqlite3.connect(str(cfg.db_path), timeout=10.0)
        if is_new:
            os.chmod(cfg.db_path, 0o600)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys=ON;")
        user_ver = int(self.conn.execute("PRAGMA user_version").fetchone()[0])
        if user_ver < self.SCHEMA_VERSION:
            os.chmod(cfg.db_path, 0o600)
            self.conn.execute("PRAGMA journal_mode=WAL;")
            self.conn.executescript(SCHEMA_SQL)
            task_cols = {
                r["name"]
                for r in self.conn.execute("PRAGMA table_info(tasks)").fetchall()
            }
            if "auto_slotted" not in task_cols:
                self.conn.execute(
                    "ALTER TABLE tasks ADD COLUMN auto_slotted INTEGER NOT NULL DEFAULT 0"
                )
            self.conn.execute(
                "INSERT OR IGNORE INTO focus (singleton, active) VALUES (1, 0)"
            )
            self.conn.execute(f"PRAGMA user_version = {self.SCHEMA_VERSION}")
            self.conn.commit()

    def close(self) -> None:
        self.conn.close()

    def get_meta(self, key: str, default: str = "") -> str:
        row = self.conn.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
        return str(row["value"]) if row else default

    def set_meta(self, key: str, value: str) -> None:
        self.conn.execute(
            "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, value),
        )
        self.conn.commit()

    def add_captured_task(self, cap: ParsedCapture, now: dt.datetime) -> str:
        stamp = to_utc_iso(now) or ""
        parent_key = f"t-{uuid.uuid4().hex[:12]}"
        self.conn.execute(
            """
            INSERT INTO tasks (
              local_key, parent_key, step_index, project_name, title, description,
              priority, estimate_min, due_at, start_at, end_at, done, dirty_op, updated_at
            ) VALUES (?, NULL, NULL, ?, ?, '', ?, ?, ?, ?, ?, 0, 'upsert', ?)
            """,
            (
                parent_key,
                cap.project,
                cap.title,
                cap.priority,
                cap.estimate_min,
                to_utc_iso(cap.due_at),
                to_utc_iso(cap.start_at),
                to_utc_iso(cap.end_at),
                stamp,
            ),
        )
        for idx, step in enumerate(cap.steps, start=1):
            step_key = f"t-{uuid.uuid4().hex[:12]}"
            self.conn.execute(
                """
                INSERT INTO tasks (
                  local_key, parent_key, step_index, project_name, title, description,
                  priority, estimate_min, due_at, done, dirty_op, updated_at
                ) VALUES (?, ?, ?, ?, ?, '', ?, ?, ?, 0, 'upsert', ?)
                """,
                (
                    step_key,
                    parent_key,
                    idx,
                    cap.project,
                    step.title,
                    cap.priority,
                    step.estimate_min or self.cfg.default_estimate_minutes,
                    to_utc_iso(cap.due_at),
                    stamp,
                ),
            )
        self.conn.commit()
        return parent_key

    def decompose_task(self, parent_key: str, raw_steps: list[str], now: dt.datetime) -> list[str]:
        parent = self.get_task(parent_key)
        if parent is None:
            raise KeyError(f"task not found: {parent_key}")
        existing = self.conn.execute(
            "SELECT COALESCE(MAX(step_index), 0) AS m FROM tasks WHERE parent_key = ? AND COALESCE(dirty_op, '') != 'delete'",
            (parent["local_key"],),
        ).fetchone()
        next_idx = int(existing["m"] if existing else 0) + 1
        stamp = to_utc_iso(now) or ""
        created_keys: list[str] = []
        for seg in raw_steps:
            ps = parse_step_segment(seg)
            if not ps.title:
                continue
            skey = f"t-{uuid.uuid4().hex[:12]}"
            self.conn.execute(
                """
                INSERT INTO tasks (
                  local_key, parent_key, step_index, project_id, project_name, title,
                  priority, estimate_min, due_at, done, dirty_op, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 'upsert', ?)
                """,
                (
                    skey,
                    parent["local_key"],
                    next_idx,
                    parent["project_id"],
                    parent["project_name"],
                    ps.title,
                    parent["priority"],
                    ps.estimate_min or self.cfg.default_estimate_minutes,
                    parent["due_at"],
                    stamp,
                ),
            )
            created_keys.append(skey)
            next_idx += 1
        self.conn.commit()
        return created_keys

    def add_captured_event(self, cap: ParsedCapture, now: dt.datetime) -> str:
        uid = f"junix-{uuid.uuid4()}"
        dtstart = cap.start_at or now
        dtend = cap.end_at or (dtstart + dt.timedelta(hours=1))
        raw_ics = build_ics_document(
            uid=uid,
            summary=cap.title,
            dtstart=dtstart,
            dtend=dtend,
            tz_name=self.cfg.timezone,
            all_day=cap.all_day,
            location=cap.location,
            rrule=cap.rrule,
        )
        stamp = to_utc_iso(now) or ""
        self.conn.execute(
            """
            INSERT INTO events (
              uid, summary, location, description, dtstart, dtend, all_day,
              rrule, exdates, raw_ics, dirty_op, updated_at
            ) VALUES (?, ?, ?, '', ?, ?, ?, ?, '', ?, 'upsert', ?)
            """,
            (
                uid,
                cap.title,
                cap.location,
                to_utc_iso(dtstart) or "",
                to_utc_iso(dtend) or "",
                1 if cap.all_day else 0,
                cap.rrule,
                raw_ics,
                stamp,
            ),
        )
        self.conn.commit()
        return uid

    def import_ics_text(self, raw_ics: str, now: dt.datetime) -> int:
        parsed = parse_ics_events(raw_ics, self.cfg.tz)
        stamp = to_utc_iso(now) or ""
        for ev in parsed:
            single_ics = build_ics_document(
                uid=ev.uid,
                summary=ev.summary,
                dtstart=ev.dtstart,
                dtend=ev.dtend,
                tz_name=self.cfg.timezone,
                all_day=ev.all_day,
                location=ev.location,
                description=ev.description,
                rrule=ev.rrule,
                exdates=ev.exdates,
            )
            ex_str = ",".join(sorted(d.isoformat() for d in ev.exdates))
            self.conn.execute(
                """
                INSERT INTO events (
                  uid, summary, location, description, dtstart, dtend, all_day,
                  rrule, exdates, raw_ics, dirty_op, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'upsert', ?)
                ON CONFLICT(uid) DO UPDATE SET
                  summary = excluded.summary,
                  location = excluded.location,
                  description = excluded.description,
                  dtstart = excluded.dtstart,
                  dtend = excluded.dtend,
                  all_day = excluded.all_day,
                  rrule = excluded.rrule,
                  exdates = excluded.exdates,
                  raw_ics = excluded.raw_ics,
                  dirty_op = 'upsert',
                  updated_at = excluded.updated_at
                """,
                (
                    ev.uid,
                    ev.summary,
                    ev.location,
                    ev.description,
                    to_utc_iso(ev.dtstart) or "",
                    to_utc_iso(ev.dtend) or "",
                    1 if ev.all_day else 0,
                    ev.rrule,
                    ex_str,
                    single_ics,
                    stamp,
                ),
            )
        self.conn.commit()
        return len(parsed)

    def get_task(self, key: str) -> sqlite3.Row | None:
        key = key.strip()
        if not key:
            return None
        row = self.conn.execute(
            "SELECT * FROM tasks WHERE local_key = ? AND COALESCE(dirty_op, '') != 'delete'",
            (key,),
        ).fetchone()
        if row is not None:
            return row
        if key.isdigit():
            return self.conn.execute(
                "SELECT * FROM tasks WHERE remote_id = ? AND COALESCE(dirty_op, '') != 'delete'",
                (int(key),),
            ).fetchone()
        if len(key) < 3:
            return None
        escaped_prefix = (
            key.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
        )
        matches = self.conn.execute(
            "SELECT * FROM tasks WHERE local_key LIKE ? ESCAPE '\\' AND COALESCE(dirty_op, '') != 'delete' LIMIT 2",
            (escaped_prefix,),
        ).fetchall()
        return matches[0] if len(matches) == 1 else None

    def mark_task_done(self, key: str, now: dt.datetime, done: bool = True) -> sqlite3.Row | None:
        row = self.get_task(key)
        if row is None:
            return None
        lkey = str(row["local_key"])
        stamp = to_utc_iso(now) or ""
        self.conn.execute(
            """
            UPDATE tasks
               SET done = ?,
                   dirty_op = 'upsert',
                   updated_at = ?
             WHERE local_key = ?
            """,
            (1 if done else 0, stamp, lkey),
        )
        self.conn.commit()
        if done:
            cur_foc = self.get_focus()
            if cur_foc["active"] and cur_foc["task_key"]:
                foc_task = self.get_task(str(cur_foc["task_key"]))
                if cur_foc["task_key"] == lkey or (foc_task and foc_task["parent_key"] == lkey):
                    focus_stop(self, now, mark_done=False, quiet_osd=True)
        return self.get_task(lkey)

    def snooze_task(self, key: str, until: dt.datetime, now: dt.datetime) -> sqlite3.Row | None:
        row = self.get_task(key)
        if row is None:
            return None
        stamp = to_utc_iso(now) or ""
        until_iso = to_utc_iso(until)
        due_dt = from_iso(row["due_at"], self.cfg.tz)
        new_due = until_iso if (due_dt is None or due_dt < until) else row["due_at"]
        self.conn.execute(
            """
            UPDATE tasks
               SET snoozed_until = ?,
                   due_at = ?,
                   dirty_op = 'upsert',
                   updated_at = ?
             WHERE local_key = ?
            """,
            (until_iso, new_due, stamp, row["local_key"]),
        )
        self.conn.commit()
        return self.get_task(row["local_key"])

    def delete_item(self, key: str, now: dt.datetime) -> bool:
        stamp = to_utc_iso(now) or ""
        t_row = self.get_task(key)
        if t_row is not None:
            lkey = t_row["local_key"]
            cur_foc = self.get_focus()
            if cur_foc["active"] and cur_foc["task_key"]:
                foc_task = self.get_task(str(cur_foc["task_key"]))
                if cur_foc["task_key"] == lkey or (foc_task and foc_task["parent_key"] == lkey):
                    focus_stop(self, now, mark_done=False)
            if t_row["remote_id"] is None:
                self.conn.execute("DELETE FROM tasks WHERE local_key = ? OR parent_key = ?", (lkey, lkey))
            else:
                self.conn.execute(
                    "UPDATE tasks SET dirty_op = 'delete', updated_at = ? WHERE local_key = ? OR parent_key = ?",
                    (stamp, lkey, lkey),
                )
            self.conn.commit()
            return True
        e_row = self.conn.execute(
            "SELECT * FROM events WHERE uid = ? AND COALESCE(dirty_op, '') != 'delete'",
            (key,),
        ).fetchone()
        if e_row is not None:
            shared_href = False
            if e_row["href"]:
                sibling = self.conn.execute(
                    "SELECT 1 FROM events WHERE href = ? AND uid != ? AND COALESCE(dirty_op, '') != 'delete' LIMIT 1",
                    (e_row["href"], key),
                ).fetchone()
                shared_href = sibling is not None
            if not e_row["href"] or shared_href:
                self.conn.execute("DELETE FROM events WHERE uid = ?", (key,))
            else:
                self.conn.execute(
                    "UPDATE events SET dirty_op = 'delete', updated_at = ? WHERE uid = ?",
                    (stamp, key),
                )
            self.conn.commit()
            return True
        return False

    def active_tasks(self) -> list[sqlite3.Row]:
        return list(
            self.conn.execute(
                "SELECT rowid AS _rowid, * FROM tasks WHERE COALESCE(dirty_op, '') != 'delete' ORDER BY done ASC, priority DESC, updated_at ASC, rowid ASC"
            ).fetchall()
        )

    def active_events(self) -> list[IcsEvent]:
        rows = self.conn.execute(
            "SELECT * FROM events WHERE COALESCE(dirty_op, '') != 'delete'"
        ).fetchall()
        out: list[IcsEvent] = []
        for r in rows:
            dtstart = from_iso(r["dtstart"], self.cfg.tz)
            dtend = from_iso(r["dtend"], self.cfg.tz)
            if dtstart is None or dtend is None:
                continue
            exdates: set[dt.date] = set()
            if r["exdates"]:
                for item in str(r["exdates"]).split(","):
                    if item:
                        try:
                            exdates.add(dt.date.fromisoformat(item))
                        except ValueError:
                            pass
            out.append(
                IcsEvent(
                    uid=r["uid"],
                    summary=r["summary"],
                    dtstart=dtstart,
                    dtend=dtend,
                    all_day=bool(r["all_day"]),
                    location=r["location"] or "",
                    description=r["description"] or "",
                    rrule=r["rrule"] or "",
                    exdates=exdates,
                    raw_ics=r["raw_ics"] or "",
                )
            )
        return out

    def get_focus(self) -> sqlite3.Row:
        return self.conn.execute("SELECT * FROM focus WHERE singleton = 1").fetchone()

    def next_sibling_step(self, task_row: sqlite3.Row) -> sqlite3.Row | None:
        parent_key = task_row["parent_key"]
        if not parent_key:
            return None
        return self.conn.execute(
            """
            SELECT * FROM tasks
             WHERE parent_key = ?
               AND local_key != ?
               AND done = 0
               AND COALESCE(dirty_op, '') != 'delete'
             ORDER BY COALESCE(step_index, 999) ASC, updated_at ASC
             LIMIT 1
            """,
            (parent_key, task_row["local_key"]),
        ).fetchone()


# ============================================================================
# Time-Aware Step Planner & Free-Gap Auto-Slotter
# ============================================================================


@dataclass
class TimelineBlock:
    kind: str  # "event", "fixed_task", "slotted_step", "free_gap"
    start: dt.datetime
    end: dt.datetime
    title: str
    key: str = ""
    subtitle: str = ""
    priority: int = 0
    step_badge: str = ""
    partial_note: str = ""
    all_day: bool = False


@dataclass
class DayPlan:
    date: dt.date
    all_day_events: list[IcsEvent]
    appointments: list[TimelineBlock]
    slotted: list[TimelineBlock]
    free_windows: list[tuple[dt.datetime, dt.datetime]]
    unscheduled_tasks: list[sqlite3.Row]
    open_count: int


def _round_up_5m(ts: dt.datetime) -> dt.datetime:
    ts = ts.replace(second=0, microsecond=0)
    rem = ts.minute % 5
    return ts if rem == 0 else ts + dt.timedelta(minutes=(5 - rem))


def subtract_busy_intervals(
    horizon_start: dt.datetime,
    horizon_end: dt.datetime,
    busy: list[tuple[dt.datetime, dt.datetime]],
) -> list[tuple[dt.datetime, dt.datetime]]:
    if horizon_end <= horizon_start:
        return []
    clipped = sorted(
        (max(horizon_start, b0), min(horizon_end, b1))
        for b0, b1 in busy
        if b1 > horizon_start and b0 < horizon_end
    )
    merged: list[tuple[dt.datetime, dt.datetime]] = []
    for s, e in clipped:
        if not merged or s > merged[-1][1]:
            merged.append((s, e))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], e))

    free: list[tuple[dt.datetime, dt.datetime]] = []
    cursor = horizon_start
    for s, e in merged:
        if s > cursor:
            free.append((cursor, s))
        cursor = max(cursor, e)
    if cursor < horizon_end:
        free.append((cursor, horizon_end))
    return [w for w in free if (w[1] - w[0]) >= dt.timedelta(minutes=10)]


def compute_day_plan(store: PlanStore, now: dt.datetime) -> DayPlan:
    tz = store.cfg.tz
    today = now.astimezone(tz).date()
    day_start = dt.datetime(
        today.year, today.month, today.day, store.cfg.day_start_hour, 0, tzinfo=tz
    )
    day_end = dt.datetime(
        today.year, today.month, today.day, store.cfg.day_end_hour, 0, tzinfo=tz
    )
    plan_cursor = _round_up_5m(max(now.astimezone(tz), day_start))
    buf = dt.timedelta(minutes=store.cfg.buffer_minutes)

    all_day_events: list[IcsEvent] = []
    appointments: list[TimelineBlock] = []
    busy: list[tuple[dt.datetime, dt.datetime]] = []

    for ev in store.active_events():
        for occ_s, occ_e in expand_event_on_date(ev, today, tz):
            if ev.all_day:
                all_day_events.append(ev)
            else:
                appointments.append(
                    TimelineBlock(
                        kind="event",
                        start=occ_s,
                        end=occ_e,
                        title=ev.summary,
                        key=ev.uid,
                        subtitle=ev.location,
                    )
                )
                busy.append((occ_s - buf, occ_e + buf))

    rows = store.active_tasks()
    by_key = {r["local_key"]: r for r in rows}
    children_by_parent: dict[str, list[sqlite3.Row]] = {}
    for r in rows:
        pk = r["parent_key"]
        if pk and pk in by_key:
            children_by_parent.setdefault(pk, []).append(r)
    for kids in children_by_parent.values():
        kids.sort(key=lambda x: (x["step_index"] or 999, x["updated_at"]))

    def _task_urgency(row_item: sqlite3.Row) -> tuple[int, int, float]:
        d_dt = from_iso(row_item["due_at"], tz)
        if d_dt is not None and d_dt.date() <= today:
            d_bucket = 0
            d_ts = d_dt.timestamp()
        elif d_dt is not None:
            d_bucket = 1
            d_ts = d_dt.timestamp()
        else:
            d_bucket = 2
            d_ts = float("inf")
        return (d_bucket, -int(row_item["priority"] or 0), d_ts)

    # Precompute parent-group urgency across parent + all undone steps so step [1/N] -> [2/N]
    # ordering never inverts when a later step carries higher priority or an earlier due date.
    parent_group_urgency: dict[str, tuple[int, int, float]] = {}
    blocked_by_snoozed_step: set[str] = set()
    for pk, kids in children_by_parent.items():
        open_steps = [k for k in kids if not k["done"]]
        if not open_steps:
            continue
        urg_candidates = [_task_urgency(by_key[pk]), *(_task_urgency(k) for k in open_steps)]
        parent_group_urgency[pk] = (
            min(u[0] for u in urg_candidates),
            min(u[1] for u in urg_candidates),
            min(u[2] for u in urg_candidates),
        )
        prior_snoozed = False
        for k in open_steps:
            snz_dt = from_iso(k["snoozed_until"], tz)
            if prior_snoozed:
                blocked_by_snoozed_step.add(str(k["local_key"]))
            elif snz_dt is not None and snz_dt > now:
                prior_snoozed = True

    open_leaf_candidates: list[tuple[tuple[int, int, float, int], sqlite3.Row, str, str]] = []
    open_count = 0

    for r in rows:
        if r["done"]:
            continue
        # Skip parent container tasks that still have open steps (schedule their ordered steps instead!)
        kids = children_by_parent.get(r["local_key"], [])
        open_kids = [k for k in kids if not k["done"]]
        if open_kids:
            continue
        open_count += 1

        snoozed = from_iso(r["snoozed_until"], tz)
        if (snoozed is not None and snoozed > now) or (str(r["local_key"]) in blocked_by_snoozed_step):
            continue

        # Explicitly pinned tasks whose window has not yet elapsed act as fixed blocks;
        # auto-slotted commits and expired undone blocks dynamically re-slot into remaining gaps.
        s_dt = from_iso(r["start_at"], tz)
        e_dt = from_iso(r["end_at"], tz)
        if (
            not r["auto_slotted"]
            and s_dt is not None
            and e_dt is not None
            and s_dt.date() == today
            and e_dt > s_dt
            and e_dt > now
        ):
            appointments.append(
                TimelineBlock(
                    kind="fixed_task",
                    start=s_dt,
                    end=e_dt,
                    title=r["title"],
                    key=r["local_key"],
                    subtitle=r["project_name"],
                    priority=int(r["priority"] or 0),
                )
            )
            busy.append((s_dt, e_dt))
            continue

        parent_title = ""
        step_badge = ""
        step_order_gate = 0
        if r["parent_key"] and r["parent_key"] in by_key:
            parent_row = by_key[r["parent_key"]]
            parent_title = parent_row["title"]
            group_order = int(parent_row["_rowid"])
            all_steps = children_by_parent[r["parent_key"]]
            pos = next(
                (idx + 1 for idx, item in enumerate(all_steps) if item["local_key"] == r["local_key"]),
                r["step_index"] or 1,
            )
            step_badge = f"[{pos}/{len(all_steps)}]"
            step_order_gate = pos
            due_bucket, neg_prio, due_ts = parent_group_urgency.get(
                r["parent_key"], _task_urgency(r)
            )
        else:
            group_order = int(r["_rowid"])
            due_bucket, neg_prio, due_ts = _task_urgency(r)

        sort_key = (
            due_bucket,
            neg_prio,
            due_ts,
            group_order,
            step_order_gate,
            int(r["_rowid"]),
        )
        open_leaf_candidates.append((sort_key, r, parent_title, step_badge))

    appointments.sort(key=lambda b: (b.start, b.end, b.title))
    open_leaf_candidates.sort(key=lambda item: item[0])

    free_windows = subtract_busy_intervals(plan_cursor, day_end, busy)
    slotted: list[TimelineBlock] = []

    # Queue of mutable items: [row, parent_title, step_badge, remaining_min, total_min]
    work_queue: list[list[Any]] = [
        [
            item[1],
            item[2],
            item[3],
            int(item[1]["estimate_min"] or store.cfg.default_estimate_minutes),
            int(item[1]["estimate_min"] or store.cfg.default_estimate_minutes),
        ]
        for item in open_leaf_candidates
    ]

    # Enforce strict step sequencing within each parent task while fitting free gaps
    for win_start, win_end in free_windows:
        cursor = win_start
        while (win_end - cursor) >= dt.timedelta(minutes=10) and work_queue:
            avail_min = int((win_end - cursor).total_seconds() // 60)
            chosen_idx: int | None = None
            seen_parents: set[str] = set()

            for idx, entry in enumerate(work_queue):
                row = entry[0]
                pk = row["parent_key"]
                if pk and pk in seen_parents:
                    # Never schedule Step 2 before Step 1 of the same parent!
                    continue
                if pk:
                    seen_parents.add(pk)
                if entry[3] <= avail_min:
                    chosen_idx = idx
                    break

            if chosen_idx is not None:
                row, ptitle, sbadge, rem_min, tot_min = work_queue.pop(chosen_idx)
                slot_end = cursor + dt.timedelta(minutes=rem_min)
                note = f"{rem_min}m/{tot_min}m" if rem_min < tot_min else f"{tot_min}m"
                slotted.append(
                    TimelineBlock(
                        kind="slotted_step",
                        start=cursor,
                        end=slot_end,
                        title=row["title"],
                        key=row["local_key"],
                        subtitle=ptitle or row["project_name"],
                        priority=int(row["priority"] or 0),
                        step_badge=sbadge,
                        partial_note=note,
                    )
                )
                cursor = slot_end + dt.timedelta(minutes=5)
            elif avail_min >= 15:
                # Split the top-priority item across this gap and the next gap
                entry = work_queue[0]
                row, ptitle, sbadge, rem_min, tot_min = entry
                chunk = avail_min
                entry[3] = rem_min - chunk
                slot_end = cursor + dt.timedelta(minutes=chunk)
                slotted.append(
                    TimelineBlock(
                        kind="slotted_step",
                        start=cursor,
                        end=slot_end,
                        title=row["title"],
                        key=row["local_key"],
                        subtitle=ptitle or row["project_name"],
                        priority=int(row["priority"] or 0),
                        step_badge=sbadge,
                        partial_note=f"part {chunk}m/{tot_min}m",
                    )
                )
                cursor = slot_end
                break
            else:
                break

    unscheduled = [entry[0] for entry in work_queue]
    return DayPlan(
        date=today,
        all_day_events=all_day_events,
        appointments=appointments,
        slotted=slotted,
        free_windows=free_windows,
        unscheduled_tasks=unscheduled,
        open_count=open_count,
    )


# ============================================================================
# Vikunja REST v1 & Radicale CalDAV Sync Engine
# ============================================================================


def build_ssl_context(cfg: PlanConfig) -> ssl.SSLContext:
    ctx = ssl.create_default_context()
    ca_candidates = [cfg.ca_cert] if cfg.ca_cert else []
    ca_candidates.append("/etc/ssl/certs/ca-certificates.crt")
    for candidate in ca_candidates:
        if candidate and Path(candidate).is_file():
            ctx.load_verify_locations(cafile=candidate)
            break
    return ctx


class VikunjaClient:
    def __init__(self, cfg: PlanConfig):
        self.cfg = cfg
        self.base = cfg.vikunja_url.rstrip("/")
        self.ssl_ctx = build_ssl_context(cfg)

    def _request_raw(
        self, method: str, path: str, payload: dict[str, Any] | None = None
    ) -> tuple[Any, dict[str, str]]:
        url = f"{self.base}{path}"
        body = json.dumps(payload).encode("utf-8") if payload is not None else None
        headers = {
            "Authorization": f"Bearer {self.cfg.vikunja_token}",
            "Accept": "application/json",
        }
        if body is not None:
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=8, context=self.ssl_ctx) as resp:
                resp_headers = {k.lower(): v for k, v in resp.headers.items()}
                raw = resp.read().decode("utf-8")
                data = json.loads(raw) if raw.strip() else None
                return data, resp_headers
        except urllib.error.HTTPError as exc:
            exc.close()
            raise

    def _request(
        self, method: str, path: str, payload: dict[str, Any] | None = None
    ) -> Any:
        return self._request_raw(method, path, payload)[0]

    def _fetch_paginated(
        self, base_path: str, per_page: int = 200, max_pages: int = 200
    ) -> tuple[list[dict[str, Any]], bool]:
        all_items: list[dict[str, Any]] = []
        page = 1
        hit_cap = False
        sep = "&" if "?" in base_path else "?"
        while page <= max_pages:
            batch, hdrs = self._request_raw(
                "GET", f"{base_path}{sep}per_page={per_page}&page={page}"
            )
            if not isinstance(batch, list) or not batch:
                break
            all_items.extend(batch)
            total_pages_raw = hdrs.get("x-pagination-total-pages")
            if total_pages_raw and total_pages_raw.isdigit():
                total_pages = int(total_pages_raw)
                if page >= total_pages:
                    break
                if page == max_pages:
                    hit_cap = True
                    break
            else:
                # Without pagination headers, Vikunja defaults maxitemsperpage to 50.
                if len(batch) < 50:
                    break
                if page == max_pages:
                    hit_cap = True
                    break
            page += 1
        return all_items, hit_cap

    def verify_user(self) -> dict[str, Any]:
        return self._request("GET", "/api/v1/user")

    def list_projects(self) -> list[dict[str, Any]]:
        return self._fetch_paginated("/api/v1/projects")[0]

    def create_project(self, title: str) -> dict[str, Any]:
        return self._request("PUT", "/api/v1/projects", {"title": title})

    def list_all_tasks(self) -> tuple[list[dict[str, Any]], bool]:
        return self._fetch_paginated("/api/v1/tasks")

    def get_task(self, task_id: int) -> dict[str, Any] | None:
        res = self._request("GET", f"/api/v1/tasks/{task_id}")
        return res if isinstance(res, dict) else None

    def create_task(self, project_id: int, payload: dict[str, Any]) -> dict[str, Any]:
        return self._request("PUT", f"/api/v1/projects/{project_id}/tasks", payload)

    def update_task(self, task_id: int, payload: dict[str, Any]) -> dict[str, Any]:
        existing = self.get_task(task_id)
        merged = {**existing, **payload} if existing else payload
        return self._request("POST", f"/api/v1/tasks/{task_id}", merged)

    def delete_task(self, task_id: int) -> None:
        self._request("DELETE", f"/api/v1/tasks/{task_id}")

    def ensure_subtask_relation(self, parent_id: int, child_id: int) -> None:
        try:
            self._request(
                "PUT",
                f"/api/v1/tasks/{parent_id}/relations",
                {"other_task_id": child_id, "relation_kind": "subtask"},
            )
        except urllib.error.HTTPError as exc:
            # 400/409 if relation already exists, 404 if parent/child was deleted concurrently
            if exc.code not in (400, 404, 409):
                raise


class RadicaleClient:
    def __init__(self, cfg: PlanConfig):
        self.cfg = cfg
        self.base = cfg.radicale_url.rstrip("/")
        self.ssl_ctx = build_ssl_context(cfg)
        raw_creds = f"{cfg.radicale_user}:{cfg.radicale_password}".encode("utf-8")
        self.auth_header = "Basic " + base64.b64encode(raw_creds).decode("ascii")

    @property
    def collection_path(self) -> str:
        if self.cfg.calendar_path:
            p = self.cfg.calendar_path.strip("/")
            return f"/{p}/"
        return f"/{urllib.parse.quote(self.cfg.radicale_user)}/personal/"

    def _request(
        self,
        method: str,
        path: str,
        body: bytes | None = None,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, dict[str, str], bytes]:
        url = path if path.startswith("http") else f"{self.base}{path}"
        req_headers = {"Authorization": self.auth_header}
        if headers:
            req_headers.update(headers)
        req = urllib.request.Request(url, data=body, headers=req_headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=8, context=self.ssl_ctx) as resp:
                resp_headers = {k.lower(): v for k, v in resp.headers.items()}
                return resp.status, resp_headers, resp.read()
        except urllib.error.HTTPError as exc:
            exc.close()
            raise

    def ensure_calendar_collection(self) -> str:
        col = self.collection_path
        propfind_xml = (
            '<?xml version="1.0" encoding="UTF-8" ?>'
            '<D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
            "<D:prop><C:supported-calendar-component-set/></D:prop>"
            "</D:propfind>"
        ).encode("utf-8")
        vevent_only_prop = (
            "<C:supported-calendar-component-set>"
            '<C:comp name="VEVENT"/>'
            "</C:supported-calendar-component-set>"
        )
        try:
            _, _, prop_body = self._request(
                "PROPFIND",
                col,
                body=propfind_xml,
                headers={"Depth": "0", "Content-Type": "application/xml; charset=utf-8"},
            )
            # Restrict existing Radicale calendar collections to VEVENT so DAVx5
            # does not also expose Junix Calendar as a VTODO list in Tasks.org.
            if b"VTODO" in prop_body:
                patch_xml = (
                    '<?xml version="1.0" encoding="UTF-8" ?>'
                    '<D:propertyupdate xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
                    f"<D:set><D:prop>{vevent_only_prop}</D:prop></D:set>"
                    "</D:propertyupdate>"
                ).encode("utf-8")
                try:
                    self._request(
                        "PROPPATCH",
                        col,
                        body=patch_xml,
                        headers={"Content-Type": "application/xml; charset=utf-8"},
                    )
                except urllib.error.HTTPError:
                    pass
            return col
        except urllib.error.HTTPError as exc:
            if exc.code != 404:
                raise
        mkcol_xml = (
            '<?xml version="1.0" encoding="UTF-8" ?>'
            '<C:mkcalendar xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
            "<D:set><D:prop>"
            "<D:displayname>Calendar</D:displayname>"
            f"{vevent_only_prop}"
            "</D:prop></D:set></C:mkcalendar>"
        ).encode("utf-8")
        try:
            self._request(
                "MKCALENDAR",
                col,
                body=mkcol_xml,
                headers={"Content-Type": "application/xml; charset=utf-8"},
            )
        except urllib.error.HTTPError:
            mkcol_dav = (
                '<?xml version="1.0" encoding="UTF-8" ?>'
                '<D:mkcol xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
                "<D:set><D:prop>"
                "<D:resourcetype><D:collection/><C:calendar/></D:resourcetype>"
                "<D:displayname>Calendar</D:displayname>"
                f"{vevent_only_prop}"
                "</D:prop></D:set></D:mkcol>"
            ).encode("utf-8")
            self._request(
                "MKCOL",
                col,
                body=mkcol_dav,
                headers={"Content-Type": "application/xml; charset=utf-8"},
            )
        return col

    def put_event(self, uid: str, raw_ics: str, href: str | None = None) -> tuple[str, str]:
        col = self.ensure_calendar_collection()
        safe_name = re.sub(r"[^A-Za-z0-9._@-]", "_", uid)
        target = href or f"{col}{safe_name}.ics"
        _, hdrs, _ = self._request(
            "PUT",
            target,
            body=raw_ics.encode("utf-8"),
            headers={"Content-Type": "text/calendar; charset=utf-8"},
        )
        return target, hdrs.get("etag", "")

    def delete_event(self, href: str) -> None:
        try:
            self._request("DELETE", href)
        except urllib.error.HTTPError as exc:
            if exc.code != 404:
                raise

    def fetch_all_vevents(self) -> list[tuple[str, str, str]]:
        col = self.ensure_calendar_collection()
        report_xml = (
            '<?xml version="1.0" encoding="utf-8" ?>'
            '<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
            "<D:prop><D:getetag/><C:calendar-data/></D:prop>"
            '<C:filter><C:comp-filter name="VCALENDAR">'
            '<C:comp-filter name="VEVENT"/>'
            "</C:comp-filter></C:filter>"
            "</C:calendar-query>"
        ).encode("utf-8")
        _, _, raw = self._request(
            "REPORT",
            col,
            body=report_xml,
            headers={
                "Depth": "1",
                "Content-Type": "application/xml; charset=utf-8",
            },
        )
        root = ET.fromstring(raw.decode("utf-8"))
        ns = {"D": "DAV:", "C": "urn:ietf:params:xml:ns:caldav"}
        results: list[tuple[str, str, str]] = []
        for resp in root.findall("D:response", ns):
            href_el = resp.find("D:href", ns)
            etag_el = resp.find(".//D:getetag", ns)
            cdata_el = resp.find(".//C:calendar-data", ns)
            if href_el is not None and cdata_el is not None and cdata_el.text:
                results.append(
                    (
                        href_el.text.strip(),
                        (etag_el.text or "").strip() if etag_el is not None else "",
                        cdata_el.text,
                    )
                )
        return results


def _acquire_sync_lock(cfg: PlanConfig, timeout_sec: float = 25.0) -> int | None:
    cfg.runtime_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_path = cfg.runtime_dir / "junix-plan-sync.lock"
    fd = os.open(str(lock_path), os.O_CREAT | os.O_RDWR, 0o600)
    deadline = time.monotonic() + timeout_sec
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except BlockingIOError:
            if time.monotonic() >= deadline:
                os.close(fd)
                return None
            time.sleep(0.05)


def sync_all(store: PlanStore, now: dt.datetime) -> dict[str, Any]:
    cfg = store.cfg
    lock_fd = _acquire_sync_lock(cfg)
    if lock_fd is None:
        return {
            "vikunja": "locked",
            "radicale": "locked",
            "errors": ["sync lock busy"],
        }

    report: dict[str, Any] = {"vikunja": "skipped", "radicale": "skipped", "errors": []}
    try:
        if cfg.has_vikunja_creds:
            try:
                _sync_vikunja(store, VikunjaClient(cfg), now)
                report["vikunja"] = "ok"
            except Exception as exc:
                report["vikunja"] = "error"
                report["errors"].append(f"vikunja: {exc}")

        if cfg.has_radicale_creds:
            try:
                _sync_radicale(store, RadicaleClient(cfg), now)
                report["radicale"] = "ok"
            except Exception as exc:
                report["radicale"] = "error"
                report["errors"].append(f"radicale: {exc}")

        status_tag = "online" if not report["errors"] and (
            report["vikunja"] == "ok" or report["radicale"] == "ok"
        ) else ("offline" if report["errors"] else "local")
        store.set_meta("last_sync_state", status_tag)
        store.set_meta("last_sync_at", to_utc_iso(now) or "")
        write_lock_status(store, now)
        return report
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        finally:
            os.close(lock_fd)


def _sync_vikunja(store: PlanStore, client: VikunjaClient, now: dt.datetime) -> None:
    cfg_default_proj = (store.cfg.default_project or "Inbox").strip() or "Inbox"
    projects = client.list_projects()
    if not projects:
        created_proj = client.create_project(cfg_default_proj)
        projects = [created_proj]
    proj_by_name = {str(p["title"]).lower(): int(p["id"]) for p in projects}
    proj_by_id = {int(p["id"]): str(p["title"]) for p in projects}
    default_proj_id = (
        proj_by_name.get(cfg_default_proj.lower())
        or proj_by_name.get("inbox")
        or int(projects[0]["id"])
    )

    for pid, ptitle in proj_by_id.items():
        store.conn.execute(
            "INSERT INTO projects (id, title) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET title = excluded.title",
            (pid, ptitle),
        )
    store.conn.commit()

    # 1. Push deletions first (never hold a SQLite write transaction across HTTP I/O!)
    del_rows = store.conn.execute(
        "SELECT * FROM tasks WHERE dirty_op = 'delete'"
    ).fetchall()
    for row in del_rows:
        if row["remote_id"] is not None:
            try:
                client.delete_task(int(row["remote_id"]))
            except urllib.error.HTTPError as exc:
                if exc.code != 404:
                    raise
        store.conn.execute("DELETE FROM tasks WHERE local_key = ?", (row["local_key"],))
        store.conn.commit()

    # 2. Push upserts (parents before child steps!)
    up_rows = store.conn.execute(
        """
        SELECT * FROM tasks
         WHERE dirty_op = 'upsert'
         ORDER BY CASE WHEN parent_key IS NULL THEN 0 ELSE 1 END ASC,
                  COALESCE(step_index, 0) ASC
        """
    ).fetchall()

    for row in up_rows:
        pname = (row["project_name"] or cfg_default_proj).strip()
        existing_pid = int(row["project_id"]) if row["project_id"] is not None else None
        pid = existing_pid if (existing_pid in proj_by_id) else proj_by_name.get(pname.lower())
        if pid is None:
            new_p = client.create_project(pname)
            pid = int(new_p["id"])
            proj_by_name[pname.lower()] = pid
            proj_by_id[pid] = pname
            store.conn.execute(
                "INSERT INTO projects (id, title) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET title = excluded.title",
                (pid, pname),
            )
            store.conn.commit()

        payload = {
            "title": row["title"],
            "description": encode_task_description(
                row["description"],
                row["estimate_min"],
                row["step_index"],
                auto_slotted=bool(row["auto_slotted"]),
                auto_start=row["start_at"],
                auto_end=row["end_at"],
            ),
            "done": bool(row["done"]),
            "priority": int(row["priority"] or 0),
            "due_date": row["due_at"] or "0001-01-01T00:00:00Z",
            "start_date": row["start_at"] or "0001-01-01T00:00:00Z",
            "end_date": row["end_at"] or "0001-01-01T00:00:00Z",
            "project_id": int(pid),
        }
        if row["remote_id"] is None:
            created = client.create_task(int(pid), payload)
            rid = int(created["id"])
            store.conn.execute(
                "UPDATE tasks SET remote_id = ?, project_id = ?, dirty_op = NULL WHERE local_key = ?",
                (rid, int(pid), row["local_key"]),
            )
            store.conn.commit()
        else:
            rid = int(row["remote_id"])
            try:
                client.update_task(rid, payload)
            except urllib.error.HTTPError as exc:
                if exc.code == 404:
                    # Task was deleted on Vikunja; drop orphaned local row instead of wedging sync
                    store.conn.execute(
                        "DELETE FROM tasks WHERE local_key = ?", (row["local_key"],)
                    )
                    store.conn.commit()
                    continue
                raise
            store.conn.execute(
                "UPDATE tasks SET project_id = ?, dirty_op = NULL WHERE local_key = ?",
                (int(pid), row["local_key"]),
            )
            store.conn.commit()

        if row["parent_key"]:
            parent_row = store.conn.execute(
                "SELECT remote_id FROM tasks WHERE local_key = ?",
                (row["parent_key"],),
            ).fetchone()
            if parent_row and parent_row["remote_id"] is not None:
                client.ensure_subtask_relation(int(parent_row["remote_id"]), rid)

    # 3. Pull remote tasks & reconcile parent/subtask relations
    remote_tasks, hit_page_cap = client.list_all_tasks()
    dirty_keys = {
        r["remote_id"]
        for r in store.conn.execute(
            "SELECT remote_id FROM tasks WHERE dirty_op IS NOT NULL AND remote_id IS NOT NULL"
        ).fetchall()
    }
    seen_remote_ids: set[int] = set()
    parent_remote_for_child: dict[int, int] = {}

    for rt in remote_tasks:
        rid = int(rt["id"])
        seen_remote_ids.add(rid)
        rel_map = rt.get("related_tasks") or {}
        if isinstance(rel_map, dict):
            for p_obj in rel_map.get("parenttask") or []:
                if isinstance(p_obj, dict) and "id" in p_obj:
                    parent_remote_for_child[rid] = int(p_obj["id"])
            for c_obj in rel_map.get("subtask") or []:
                if isinstance(c_obj, dict) and "id" in c_obj:
                    parent_remote_for_child[int(c_obj["id"])] = rid

        if rid in dirty_keys:
            continue

        clean_desc, est_min, step_idx, desc_auto = decode_task_description(
            rt.get("description")
        )
        meta_auto_s, meta_auto_e = _decode_task_meta_window(rt.get("description"))
        pid = int(rt.get("project_id") or default_proj_id)
        pname = proj_by_id.get(pid, cfg_default_proj)
        due_iso = to_utc_iso(from_iso(rt.get("due_date"), store.cfg.tz))
        start_iso = to_utc_iso(from_iso(rt.get("start_date"), store.cfg.tz))
        end_iso = to_utc_iso(from_iso(rt.get("end_date"), store.cfg.tz))
        updated_iso = to_utc_iso(from_iso(rt.get("updated"), store.cfg.tz)) or (
            to_utc_iso(now) or ""
        )
        meta_matches_window = bool(
            meta_auto_s and start_iso == meta_auto_s and end_iso == meta_auto_e
        )

        existing = store.conn.execute(
            "SELECT local_key, estimate_min, step_index, start_at, end_at, auto_slotted FROM tasks WHERE remote_id = ?",
            (rid,),
        ).fetchone()
        if existing:
            window_unchanged = (existing["start_at"] == start_iso and existing["end_at"] == end_iso)
            web_ui_pinned = False
            if start_iso is None:
                auto_flag = 0
            elif meta_auto_s is not None:
                auto_flag = 1 if (desc_auto and meta_matches_window) else 0
                if desc_auto and not meta_matches_window:
                    web_ui_pinned = True
            elif existing["auto_slotted"] and not window_unchanged:
                auto_flag = 0
                web_ui_pinned = True
            elif not existing["auto_slotted"] and window_unchanged:
                auto_flag = 0
            else:
                auto_flag = 1 if desc_auto else 0
            store.conn.execute(
                """
                UPDATE tasks
                   SET project_id = ?,
                       project_name = ?,
                       title = ?,
                       description = ?,
                       priority = ?,
                       estimate_min = COALESCE(?, estimate_min),
                       step_index = COALESCE(?, step_index),
                       due_at = ?,
                       start_at = ?,
                       end_at = ?,
                       auto_slotted = ?,
                       done = ?,
                       dirty_op = CASE WHEN ? THEN 'upsert' ELSE dirty_op END,
                       updated_at = ?
                 WHERE remote_id = ?
                """,
                (
                    pid,
                    pname,
                    rt.get("title") or "Untitled",
                    clean_desc,
                    int(rt.get("priority") or 0),
                    est_min,
                    step_idx,
                    due_iso,
                    start_iso,
                    end_iso,
                    auto_flag,
                    1 if rt.get("done") else 0,
                    1 if web_ui_pinned else 0,
                    updated_iso,
                    rid,
                ),
            )
        else:
            init_auto = 0
            if desc_auto and start_iso is not None:
                init_auto = 1 if (meta_auto_s is None or meta_matches_window) else 0
            store.conn.execute(
                """
                INSERT INTO tasks (
                  local_key, remote_id, project_id, project_name, title, description,
                  priority, estimate_min, step_index, due_at, start_at, end_at,
                  auto_slotted, done, dirty_op, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)
                """,
                (
                    f"vk-{rid}",
                    rid,
                    pid,
                    pname,
                    rt.get("title") or "Untitled",
                    clean_desc,
                    int(rt.get("priority") or 0),
                    est_min,
                    step_idx,
                    due_iso,
                    start_iso,
                    end_iso,
                    init_auto,
                    1 if rt.get("done") else 0,
                    updated_iso,
                ),
            )

    # Wire parent_key links from Vikunja relations (and clear stale links removed remotely)
    remote_to_local = {
        int(r["remote_id"]): str(r["local_key"])
        for r in store.conn.execute(
            "SELECT local_key, remote_id FROM tasks WHERE remote_id IS NOT NULL"
        ).fetchall()
    }
    linked_child_keys: set[str] = set()
    for child_rid, parent_rid in parent_remote_for_child.items():
        cl = remote_to_local.get(child_rid)
        pl = remote_to_local.get(parent_rid)
        if cl and pl:
            linked_child_keys.add(cl)
            store.conn.execute(
                "UPDATE tasks SET parent_key = ? WHERE local_key = ? AND dirty_op IS NULL",
                (pl, cl),
            )
    for rid, lkey in remote_to_local.items():
        if rid in seen_remote_ids and lkey not in linked_child_keys and rid not in dirty_keys:
            store.conn.execute(
                """
                UPDATE tasks
                   SET parent_key = NULL
                 WHERE local_key = ?
                   AND dirty_op IS NULL
                   AND parent_key IN (SELECT local_key FROM tasks WHERE remote_id IS NOT NULL)
                """,
                (lkey,),
            )

    # Prune synced tasks deleted on another device (only when full task list was fetched)
    if not hit_page_cap:
        for rid, lkey in list(remote_to_local.items()):
            if rid not in seen_remote_ids and rid not in dirty_keys:
                store.conn.execute(
                    "DELETE FROM tasks WHERE local_key = ? AND dirty_op IS NULL", (lkey,)
                )
    store.conn.commit()

    # Release active Focus / owned DND if the focused task was completed or deleted remotely
    cur_foc = store.get_focus()
    if cur_foc["active"] and cur_foc["task_key"]:
        foc_row = store.get_task(str(cur_foc["task_key"]))
        if foc_row is None or bool(foc_row["done"]):
            focus_stop(store, now, mark_done=False, quiet_osd=True)


def _sync_radicale(store: PlanStore, client: RadicaleClient, now: dt.datetime) -> None:
    del_rows = store.conn.execute(
        "SELECT * FROM events WHERE dirty_op = 'delete'"
    ).fetchall()
    for row in del_rows:
        if row["href"]:
            client.delete_event(str(row["href"]))
        store.conn.execute("DELETE FROM events WHERE uid = ?", (row["uid"],))
        store.conn.commit()

    up_rows = store.conn.execute(
        "SELECT * FROM events WHERE dirty_op = 'upsert'"
    ).fetchall()
    for row in up_rows:
        raw_ics = row["raw_ics"]
        if not raw_ics:
            dtstart = from_iso(row["dtstart"], store.cfg.tz) or now
            dtend = from_iso(row["dtend"], store.cfg.tz) or (dtstart + dt.timedelta(hours=1))
            ex_dates = [
                dt.date.fromisoformat(s)
                for s in (row["exdates"] or "").split(",")
                if s.strip()
            ]
            raw_ics = build_ics_document(
                uid=row["uid"],
                summary=row["summary"],
                dtstart=dtstart,
                dtend=dtend,
                tz_name=store.cfg.timezone,
                all_day=bool(row["all_day"]),
                location=row["location"] or "",
                description=row["description"] or "",
                rrule=row["rrule"] or "",
                exdates=ex_dates,
            )
        href, etag = client.put_event(row["uid"], raw_ics, row["href"] or None)
        store.conn.execute(
            "UPDATE events SET href = ?, etag = ?, raw_ics = ?, dirty_op = NULL WHERE uid = ?",
            (href, etag, raw_ics, row["uid"]),
        )
        store.conn.commit()

    dirty_uids = {
        r["uid"]
        for r in store.conn.execute(
            "SELECT uid FROM events WHERE dirty_op IS NOT NULL"
        ).fetchall()
    }
    seen_uids: set[str] = set()
    stamp = to_utc_iso(now) or ""

    for href, etag, cdata in client.fetch_all_vevents():
        for ev in parse_ics_events(cdata, store.cfg.tz):
            seen_uids.add(ev.uid)
            if ev.uid in dirty_uids:
                continue
            ex_str = ",".join(sorted(d.isoformat() for d in ev.exdates))
            store.conn.execute(
                """
                INSERT INTO events (
                  uid, href, etag, summary, location, description,
                  dtstart, dtend, all_day, rrule, exdates, raw_ics, dirty_op, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)
                ON CONFLICT(uid) DO UPDATE SET
                  href = excluded.href,
                  etag = excluded.etag,
                  summary = excluded.summary,
                  location = excluded.location,
                  description = excluded.description,
                  dtstart = excluded.dtstart,
                  dtend = excluded.dtend,
                  all_day = excluded.all_day,
                  rrule = excluded.rrule,
                  exdates = excluded.exdates,
                  raw_ics = excluded.raw_ics,
                  updated_at = excluded.updated_at
                """,
                (
                    ev.uid,
                    href,
                    etag,
                    ev.summary,
                    ev.location,
                    ev.description,
                    to_utc_iso(ev.dtstart) or "",
                    to_utc_iso(ev.dtend) or "",
                    1 if ev.all_day else 0,
                    ev.rrule,
                    ex_str,
                    cdata,
                    stamp,
                ),
            )

    existing_synced = store.conn.execute(
        "SELECT uid FROM events WHERE dirty_op IS NULL AND href IS NOT NULL"
    ).fetchall()
    for row in existing_synced:
        if row["uid"] not in seen_uids:
            store.conn.execute("DELETE FROM events WHERE uid = ?", (row["uid"],))
    store.conn.commit()


# ============================================================================
# Hyprland Desktop Surfaces: Focus Mode, Mako DND, SwayOSD, Pulse, & Hyprlock
# ============================================================================


def _run_quiet(cmd: list[str], timeout: float = 3.0) -> tuple[int, str]:
    exe = shutil.which(cmd[0])
    if not exe:
        return 127, ""
    try:
        proc = subprocess.run(
            [exe, *cmd[1:]],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout.strip()
    except Exception:
        return 1, ""


def _spawn_detached(cmd: list[str]) -> bool:
    exe = shutil.which(cmd[0])
    if not exe:
        return False
    try:
        subprocess.Popen(
            [exe, *cmd[1:]],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True
    except Exception:
        return False


def is_mako_dnd_active() -> bool:
    rc, out = _run_quiet(["makoctl", "mode"])
    return rc == 0 and "do-not-disturb" in out.splitlines()


def set_mako_dnd(enable: bool) -> None:
    flag = "-a" if enable else "-r"
    _run_quiet(["makoctl", "mode", flag, "do-not-disturb"])


def show_osd(message: str) -> None:
    _run_quiet(["swayosd-client", "--custom-message", message])


def format_minutes_human(minutes: int) -> str:
    minutes = max(0, int(minutes))
    if minutes < 60:
        return f"{minutes}m"
    h, m = divmod(minutes, 60)
    return f"{h}h {m}m" if m else f"{h}h"


def progress_bar(elapsed_min: float, total_min: float, width: int = 8) -> str:
    total = max(1.0, total_min)
    ratio = max(0.0, min(1.0, elapsed_min / total))
    filled = min(width, int(round(ratio * width)))
    empty = max(0, width - filled)
    return ("━" * filled) + "●" + ("─" * empty)


def focus_start(
    store: PlanStore, key: str, now: dt.datetime, override_minutes: int | None = None
) -> str:
    row = store.get_task(key)
    if row is None:
        raise KeyError(f"task not found: {key}")

    # End any existing focus first without flapping DND
    cur = store.get_focus()
    already_owned = bool(cur["active"] and cur["dnd_owned"])

    dur = override_minutes or int(row["estimate_min"] or store.cfg.default_estimate_minutes)
    dur = max(5, dur)
    parent_title = ""
    if row["parent_key"]:
        prow = store.get_task(row["parent_key"])
        if prow:
            parent_title = str(prow["title"])

    dnd_owned = already_owned
    if store.cfg.auto_dnd and not already_owned:
        if not is_mako_dnd_active():
            set_mako_dnd(True)
            dnd_owned = True

    ends = now + dt.timedelta(minutes=dur)
    store.conn.execute(
        """
        UPDATE focus
           SET active = 1,
               task_key = ?,
               title = ?,
               parent_title = ?,
               started_at = ?,
               ends_at = ?,
               duration_min = ?,
               dnd_owned = ?,
               completed_prompted = 0
         WHERE singleton = 1
        """,
        (
            row["local_key"],
            row["title"],
            parent_title,
            to_utc_iso(now),
            to_utc_iso(ends),
            dur,
            1 if dnd_owned else 0,
        ),
    )
    store.conn.commit()
    write_lock_status(store, now)
    dnd_tag = " · DND on" if (dnd_owned or is_mako_dnd_active()) else ""
    msg = f"Focus: {row['title']} ({dur}m){dnd_tag}"
    show_osd(msg)
    return msg


def focus_stop(
    store: PlanStore,
    now: dt.datetime,
    mark_done: bool = False,
    quiet_osd: bool = False,
) -> str:
    cur = store.get_focus()
    if not cur["active"]:
        return "No active focus session"
    task_key = cur["task_key"]
    title = cur["title"]
    dnd_owned = bool(cur["dnd_owned"])

    store.conn.execute(
        """
        UPDATE focus
           SET active = 0,
               task_key = NULL,
               title = '',
               parent_title = '',
               started_at = NULL,
               ends_at = NULL,
               dnd_owned = 0,
               completed_prompted = 0
         WHERE singleton = 1
        """
    )
    store.conn.commit()
    if dnd_owned:
        set_mako_dnd(False)

    next_step: sqlite3.Row | None = None
    if mark_done and task_key:
        completed = store.mark_task_done(task_key, now, done=True)
        if completed is not None:
            next_step = store.next_sibling_step(completed)

    write_lock_status(store, now)

    if mark_done:
        if next_step is not None:
            msg = f"Done: {title} · Next: {next_step['title']}"
        else:
            msg = f"Completed: {title}"
    else:
        msg = f"Stopped focus: {title}"
    if not quiet_osd:
        show_osd(msg)
    return msg


def focus_extend(store: PlanStore, minutes: int, now: dt.datetime) -> str:
    cur = store.get_focus()
    if not cur["active"]:
        return "No active focus session"
    base_end = from_iso(cur["ends_at"], store.cfg.tz) or now
    new_end = max(now, base_end) + dt.timedelta(minutes=minutes)
    new_dur = int(cur["duration_min"] or 25) + minutes
    dnd_owned = int(cur["dnd_owned"] or 0)
    if store.cfg.auto_dnd and not dnd_owned and not is_mako_dnd_active():
        set_mako_dnd(True)
        dnd_owned = 1
    store.conn.execute(
        "UPDATE focus SET ends_at = ?, duration_min = ?, dnd_owned = ?, completed_prompted = 0 WHERE singleton = 1",
        (to_utc_iso(new_end), new_dur, dnd_owned, ),
    )
    store.conn.commit()
    write_lock_status(store, now)
    msg = f"Focus +{minutes}m: {cur['title']}"
    show_osd(msg)
    return msg


def build_pulse_summary(store: PlanStore, now: dt.datetime) -> tuple[str, str]:
    local_now = now.astimezone(store.cfg.tz)
    wd = GERMAN_WEEKDAYS[local_now.weekday()]
    mo = GERMAN_MONTHS[local_now.month]
    header = f"{local_now:%H:%M} Uhr  •  {wd}, {local_now.day}. {mo}"

    plan = compute_day_plan(store, local_now)
    focus = store.get_focus()
    lines: list[str] = []

    if focus["active"]:
        s_at = from_iso(focus["started_at"], store.cfg.tz) or local_now
        e_at = from_iso(focus["ends_at"], store.cfg.tz) or local_now
        dur_m = max(1, int(focus["duration_min"] or 25))
        rem_m = max(0, int(round((e_at - local_now).total_seconds() / 60.0)))
        el_m = max(0.0, (local_now - s_at).total_seconds() / 60.0)
        header = f"{local_now:%H:%M} Uhr  •  Focus {rem_m}m left"
        lines.append(
            f"▶ <b>{html.escape(str(focus['title']))}</b>\n"
            f"  {progress_bar(el_m, dur_m)}  {int(el_m)}/{dur_m}m"
        )

    upcoming_ev = next((b for b in plan.appointments if b.end > local_now), None)
    if upcoming_ev is not None:
        if upcoming_ev.start <= local_now:
            left_m = int((upcoming_ev.end - local_now).total_seconds() // 60)
            lines.append(
                f"󰃭 <b>Now: {html.escape(upcoming_ev.title)}</b> ({format_minutes_human(left_m)} left)"
            )
        else:
            until_m = int((upcoming_ev.start - local_now).total_seconds() // 60)
            lines.append(
                f"󰃭 <b>{upcoming_ev.start:%H:%M}</b> {html.escape(upcoming_ev.title)} (in {format_minutes_human(until_m)})"
            )
    elif plan.free_windows:
        fw_s, fw_e = plan.free_windows[0]
        free_m = int((fw_e - max(local_now, fw_s)).total_seconds() // 60)
        lines.append(f"󰃭 Clear schedule ({format_minutes_human(free_m)} open today)")

    if not focus["active"] and plan.slotted:
        nxt = plan.slotted[0]
        badge = f"{nxt.step_badge} " if nxt.step_badge else ""
        lines.append(
            f"󰄬 Next: <b>{html.escape(badge + nxt.title)}</b> ({nxt.partial_note}) · {plan.open_count} open"
        )
    else:
        lines.append(f"󰄬 {plan.open_count} open task(s)")

    return header, "\n".join(lines)


def _truncate_label(text: str, max_chars: int) -> str:
    if len(text) <= max_chars:
        return text
    return text[: max(1, max_chars - 1)] + "…"


def _format_block_span(blk: TimelineBlock, day: dt.date, sep: str = "–") -> str:
    s_txt = "00:00" if blk.start.date() < day else f"{blk.start:%H:%M}"
    e_txt = "24:00" if blk.end.date() > day else f"{blk.end:%H:%M}"
    return f"{s_txt}{sep}{e_txt}"


def format_lock_line(store: PlanStore, now: dt.datetime) -> str:
    local_now = now.astimezone(store.cfg.tz)
    plan = compute_day_plan(store, local_now)
    focus = store.get_focus()
    upcoming_ev = next((b for b in plan.appointments if b.end > local_now), None)
    both_active = bool(focus["active"] and upcoming_ev is not None)
    parts: list[str] = []

    if focus["active"]:
        e_at = from_iso(focus["ends_at"], store.cfg.tz) or local_now
        rem_m = max(0, int(round((e_at - local_now).total_seconds() / 60.0)))
        ftitle = _truncate_label(str(focus["title"]), 14 if both_active else 22)
        parts.append(f"󰓾  {ftitle} ({rem_m}m)")

    if upcoming_ev is not None:
        etitle = _truncate_label(upcoming_ev.title, 12 if both_active else 20)
        if upcoming_ev.start <= local_now:
            parts.append(f"󰃭  Now: {etitle}")
        else:
            mins = int((upcoming_ev.start - local_now).total_seconds() // 60)
            parts.append(f"󰃭  {upcoming_ev.start:%H:%M} {etitle} ({format_minutes_human(mins)})")
    elif not parts and plan.slotted:
        stitle = _truncate_label(plan.slotted[0].title, 22)
        parts.append(f"󰄬  {stitle}")

    parts.append(f"󰝖  {plan.open_count} open")
    line = "  •  ".join(parts)
    if len(line) > 62 and len(parts) == 3 and upcoming_ev is not None:
        # Hard cap so 3-segment lines never overflow the 620px hyprlock top-center pill:
        # omit the relative "(1h 30m)" suffix first (clock is right below on hyprlock),
        # then trim titles if still above 62 chars.
        etitle_compact = _truncate_label(upcoming_ev.title, 12)
        if upcoming_ev.start <= local_now:
            parts[1] = f"󰃭  Now: {etitle_compact}"
        else:
            parts[1] = f"󰃭  {upcoming_ev.start:%H:%M} {etitle_compact}"
        line = "  •  ".join(parts)
        if len(line) > 62:
            over = len(line) - 62
            ftitle_compact = _truncate_label(str(focus["title"]), max(6, 14 - over))
            parts[0] = f"󰓾  {ftitle_compact} ({rem_m}m)"
            line = "  •  ".join(parts)
    return html.escape(line)


def write_lock_status(store: PlanStore, now: dt.datetime) -> str:
    line = format_lock_line(store, now)
    desired = line + "\n"
    target = store.cfg.lock_status_path
    try:
        if target.is_file() and target.read_text(encoding="utf-8") == desired:
            return line
        atomic_write(target, desired, mode=0o600)
    except OSError:
        pass
    return line


def opportunistic_background_sync(cfg: PlanConfig) -> None:
    if not (cfg.has_vikunja_creds or cfg.has_radicale_creds):
        return
    try:
        subprocess.Popen(
            [sys.executable, "-B", str(Path(__file__).resolve()), "sync", "--quiet"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass


# ============================================================================
# Interactive Rofi Day Hub (Gruvbox Material Frosted Palette)
# ============================================================================


ROFI_MESSAGE_STYLE = (
    "message { color: @fg1; padding: 10px 14px; border: 0px 4px 2px 4px; "
    "border-color: @fg1; background-color: transparent; } "
    "textbox { text-color: @fg1; background-color: transparent; }"
)

ROFI_THEME_MAIN = (
    "window { width: 860px; height: 560px; } "
    "listview { columns: 1; lines: 11; fixed-height: false; } "
    "element { orientation: horizontal; children: [ element-text ]; padding: 9px 14px; } "
    "element-text { horizontal-align: 0.0; margin: 0px; } "
    + ROFI_MESSAGE_STYLE
)

ROFI_THEME_SUB = (
    "window { width: 620px; height: 340px; } "
    "listview { columns: 1; lines: 7; fixed-height: false; } "
    "element { orientation: horizontal; children: [ element-text ]; padding: 9px 14px; } "
    "element-text { horizontal-align: 0.0; margin: 0px; } "
    + ROFI_MESSAGE_STYLE
)

ROFI_THEME_INPUT = (
    "window { width: 820px; height: 0px; } "
    "listview { enabled: false; } "
    "message { color: @fg1; padding: 10px 14px; border: 0px 4px 4px 4px; "
    "border-color: @fg1; border-radius: 0px 0px 20px 20px; background-color: transparent; } "
    "textbox { text-color: @fg1; background-color: transparent; }"
)


def _sanitize_rofi_row(label: str) -> str:
    return label.replace("\r", " ").replace("\n", " ")


def _rofi_prompt(
    prompt: str,
    rows: list[str],
    mesg: str = "",
    theme_str: str = ROFI_THEME_MAIN,
    enable_shortcuts: bool = False,
) -> tuple[int, int, str, str]:
    rofi_bin = shutil.which("rofi")
    if not rofi_bin:
        raise RuntimeError("rofi is not installed on PATH")
    cmd = [
        rofi_bin,
        "-dmenu",
        "-i",
        "-markup-rows",
        "-p",
        prompt,
        "-format",
        "i\tf\ts",
        "-theme-str",
        theme_str,
    ]
    if enable_shortcuts:
        cmd.extend(
            [
                "-kb-custom-1",
                "Alt+1",
                "-kb-custom-2",
                "Alt+2",
                "-kb-custom-3",
                "Alt+3",
                "-kb-custom-4",
                "Alt+4",
                "-kb-custom-5",
                "Alt+Return",
            ]
        )
    if mesg:
        cmd.extend(["-mesg", mesg])
    safe_rows = [_sanitize_rofi_row(r) for r in rows]
    proc = subprocess.run(
        cmd,
        input="\n".join(safe_rows),
        capture_output=True,
        text=True,
        check=False,
    )
    valid_codes = {0, 10, 11, 12, 13, 14} if enable_shortcuts else {0}
    if proc.returncode not in valid_codes:
        return proc.returncode, -1, "", ""
    out = proc.stdout.rstrip("\n")
    if not out:
        return proc.returncode, -1, "", ""
    parts = out.split("\t", 2)
    if len(parts) == 3:
        idx_str, filt_str, sel_str = parts
        try:
            return proc.returncode, int(idx_str), filt_str, sel_str
        except ValueError:
            return proc.returncode, -1, filt_str, sel_str
    if len(parts) == 2:
        idx_str, sel_str = parts
        try:
            return proc.returncode, int(idx_str), sel_str, sel_str
        except ValueError:
            return proc.returncode, -1, sel_str, sel_str
    return proc.returncode, -1, out, out


def run_rofi_capture_only(store: PlanStore) -> int:
    rc, _, filt_text, sel_text = _rofi_prompt(
        "Quick Add",
        [],
        mesg=(
            "<b>Tasks:</b> <tt>+ title tomorrow 16:00 ~45m !high #uni &gt;&gt; step 1 ~20m</tt>\n"
            "<span alpha='80%'><b>Events:</b> <tt>@ Dentist 24.11. 14:30-15:15 @Clinic weekly</tt></span>"
        ),
        theme_str=ROFI_THEME_INPUT,
    )
    typed = filt_text.strip() or sel_text.strip()
    if rc != 0 or not typed:
        return 0
    _handle_quick_input(store, typed)
    return 0


def _handle_quick_input(store: PlanStore, raw: str) -> None:
    now = now_local(store.cfg)
    cap = parse_quick_capture(
        raw,
        now,
        default_kind="task",
        default_project=store.cfg.default_project,
        default_estimate_minutes=store.cfg.default_estimate_minutes,
    )
    if cap.kind == "event":
        store.add_captured_event(cap, now)
        when = f"{cap.start_at:%d.%m. %H:%M}" if cap.start_at else "scheduled"
        show_osd(f"Event added: {cap.title} ({when})")
    else:
        store.add_captured_task(cap, now)
        step_note = f" ({len(cap.steps)} steps)" if cap.steps else ""
        show_osd(f"Added: {cap.title}{step_note}")
    write_lock_status(store, now)
    opportunistic_background_sync(store.cfg)


def run_rofi_hub(store: PlanStore) -> int:
    now = now_local(store.cfg)
    plan = compute_day_plan(store, now)
    focus = store.get_focus()
    sync_state = store.get_meta("last_sync_state", "local")

    # Build header banner
    if focus["active"]:
        e_at = from_iso(focus["ends_at"], store.cfg.tz) or now
        rem_m = max(0, int(round((e_at - now).total_seconds() / 60.0)))
        banner_top = (
            f"<b>󰓾  FOCUS:</b> {html.escape(str(focus['title']))} — <b>{rem_m}m remaining</b>  •  Sync: {html.escape(sync_state)}"
        )
    elif plan.free_windows:
        fw_s, fw_e = plan.free_windows[0]
        gap_m = int((fw_e - max(now, fw_s)).total_seconds() // 60)
        next_ev = next((b for b in plan.appointments if b.start > now), None)
        until_txt = f"until {next_ev.start:%H:%M} {html.escape(next_ev.title)}" if next_ev else "until end of day"
        banner_top = (
            f"<b>󰅐  {format_minutes_human(gap_m)} free</b> {until_txt}  •  "
            f"<b>{plan.open_count}</b> open  •  Sync: {html.escape(sync_state)}"
        )
    else:
        banner_top = f"<b>󰃭  {now:%A, %d.%m.}</b>  •  <b>{plan.open_count}</b> open  •  Sync: {html.escape(sync_state)}"

    mesg = (
        f"{banner_top}\n"
        "<span size='small' alpha='78%'>Type <tt>+ task ~30m !high &gt;&gt; step1 ~15m</tt> or <tt>@ Event 14:00-15:00</tt>  •  "
        "Enter: Done · Alt+1: Focus · Alt+2: +15m · Alt+3: Steps · Alt+4: Sync · Alt+Enter: Menu</span>"
    )

    entries: list[tuple[str, str, str]] = []  # (action_kind, target_key, label_markup)

    if focus["active"]:
        entries.append(
            ("focus_done", "", "<b>󰄬  Complete Focus Step &amp; Mark Done</b>")
        )
        entries.append(("focus_ext", "", "󰅐  Extend Focus Session (+10m)"))
        entries.append(("focus_stop", "", "✕  Stop Focus Session"))

    # Merge today's appointments and auto-slotted steps chronologically
    timeline = sorted(plan.appointments + plan.slotted, key=lambda b: (b.start, 0 if b.kind == "event" else 1))
    for ev in plan.all_day_events:
        entries.append(
            (
                "event",
                ev.uid,
                f"󰃭 <b>[All Day]</b>  {html.escape(ev.summary)}",
            )
        )
    for blk in timeline:
        span = _format_block_span(blk, plan.date, sep="–")
        if blk.kind == "event":
            loc = f" · <i>{html.escape(blk.subtitle)}</i>" if blk.subtitle else ""
            entries.append(
                ("event", blk.key, f"󰃭 <b>{span}</b>  {html.escape(blk.title)}{loc}")
            )
        elif blk.kind == "fixed_task":
            entries.append(
                ("task", blk.key, f"󰐃 <b>{span}</b>  {html.escape(blk.title)}  <span size='small'>[{html.escape(blk.subtitle)}]</span>")
            )
        else:
            p_mark = "!" * blk.priority if blk.priority > 0 else ""
            badge = f"<b>{html.escape(blk.step_badge)}</b> " if blk.step_badge else ""
            sub = f" · <span size='small'>{html.escape(blk.subtitle)}</span>" if blk.subtitle else ""
            p_str = f" <b>{p_mark}</b>" if p_mark else ""
            entries.append(
                (
                    "task",
                    blk.key,
                    f"󰄱 <tt>{span}</tt>  {badge}{html.escape(blk.title)} <span size='small'>({html.escape(blk.partial_note)})</span>{p_str}{sub}",
                )
            )

    for row in plan.unscheduled_tasks[:12]:
        est = int(row["estimate_min"] or store.cfg.default_estimate_minutes)
        entries.append(
            (
                "task",
                str(row["local_key"]),
                f"◦ <tt>Queue      </tt>  {html.escape(str(row['title']))} <span size='small'>(~{est}m · {html.escape(str(row['project_name']))})</span>",
            )
        )

    entries.append(("capture_dialog", "", "󰐕  Quick-add task, steps, or appointment…"))
    if plan.slotted:
        entries.append(("commit_day", "", "󰃭  Commit today's auto-slotted times to Vikunja"))
    entries.append(("sync", "", "󰑐  Sync now with junixsrv"))
    if shutil.which("dcal"):
        entries.append(("open_calendar", "", "󰃭  Open Dux Calendar (week / month grid)"))
    if store.cfg.vikunja_url:
        entries.append(("open_web", "", f"󰖟  Open {html.escape(store.cfg.vikunja_url)}"))

    rc, idx, filt_text, sel_text = _rofi_prompt(
        "Day Plan",
        [e[2] for e in entries],
        mesg=mesg,
        enable_shortcuts=True,
    )
    if rc not in (0, 10, 11, 12, 13, 14):
        return 0

    # Alt+4 syncs immediately regardless of selection
    if rc == 13:
        res = sync_all(store, now_local(store.cfg))
        show_osd("Sync offline — changes queued locally" if res["errors"] else "Synced with junixsrv")
        return 0

    # Direct typed quick-capture when user entered `+ ...` / `@ ...` or free unmatched text in Rofi!
    typed_filter = filt_text.strip()
    if rc == 0 and typed_filter.startswith(("+ ", "@ ")) and typed_filter not in ("+", "@"):
        _handle_quick_input(store, typed_filter)
        return 0
    if idx < 0 or idx >= len(entries):
        fallback_txt = typed_filter or sel_text.strip()
        if rc == 0 and fallback_txt:
            _handle_quick_input(store, fallback_txt)
        return 0

    kind, key, _ = entries[idx]
    if kind == "task" and rc in (10, 11, 12, 14):
        ts = now_local(store.cfg)
        t_row = store.get_task(key)
        if t_row is None:
            return 0
        if rc == 10:  # Alt+1 -> Focus
            focus_start(store, key, ts)
        elif rc == 11:  # Alt+2 -> Snooze +15m
            store.snooze_task(key, ts + dt.timedelta(minutes=15), ts)
            write_lock_status(store, ts)
            show_osd(f"Snoozed +15m: {t_row['title']}")
            opportunistic_background_sync(store.cfg)
        elif rc == 12:  # Alt+3 -> Decompose steps
            _prompt_decompose_steps(store, key, str(t_row["title"]))
        elif rc == 14:  # Alt+Return -> Action submenu
            _run_rofi_task_submenu(store, key)
        return 0

    if kind == "focus_done":
        focus_stop(store, now_local(store.cfg), mark_done=True)
        opportunistic_background_sync(store.cfg)
    elif kind == "focus_ext":
        focus_extend(store, 10, now_local(store.cfg))
    elif kind == "focus_stop":
        focus_stop(store, now_local(store.cfg), mark_done=False)
    elif kind == "capture_dialog":
        run_rofi_capture_only(store)
    elif kind == "commit_day":
        commit_day_plan(store, plan, now_local(store.cfg))
        show_osd(f"Committed {len({b.key for b in plan.slotted})} time blocks to Vikunja")
        opportunistic_background_sync(store.cfg)
    elif kind == "sync":
        res = sync_all(store, now_local(store.cfg))
        if res["errors"]:
            show_osd("Sync offline — changes queued locally")
        else:
            show_osd("Synced with junixsrv")
    elif kind == "open_calendar":
        _spawn_detached(["dcal", "show"])
    elif kind == "open_web":
        _run_quiet(["xdg-open", store.cfg.vikunja_url])
    elif kind == "task":
        ts = now_local(store.cfg)
        cur_focus = store.get_focus()
        if cur_focus["active"] and cur_focus["task_key"] == key:
            focus_stop(store, ts, mark_done=True)
            opportunistic_background_sync(store.cfg)
        else:
            t_row = store.get_task(key)
            if t_row is not None:
                new_done = not bool(t_row["done"])
                store.mark_task_done(key, ts, done=new_done)
                write_lock_status(store, ts)
                show_osd(f"{'Done' if new_done else 'Reopened'}: {t_row['title']}")
                opportunistic_background_sync(store.cfg)
    elif kind == "event":
        _run_rofi_event_submenu(store, key)
    return 0


def _prompt_decompose_steps(store: PlanStore, key: str, title: str) -> None:
    rc2, _, filt_steps, sel_steps = _rofi_prompt(
        "Steps (>> or ,)",
        [],
        mesg=(
            f"Break <b>{html.escape(title)}</b> into ordered timed steps:\n"
            "<span alpha='80%'><tt>Read notes ~20m &gt;&gt; Draft solution ~40m &gt;&gt; Review ~15m</tt></span>"
        ),
        theme_str=ROFI_THEME_INPUT,
    )
    raw_steps = filt_steps.strip() or sel_steps.strip()
    if rc2 == 0 and raw_steps:
        sep = ">>" if ">>" in raw_steps else ","
        parts = [p.strip() for p in raw_steps.split(sep) if p.strip()]
        created = store.decompose_task(key, parts, now_local(store.cfg))
        write_lock_status(store, now_local(store.cfg))
        show_osd(f"Added {len(created)} step(s) to {title}")
        opportunistic_background_sync(store.cfg)


def _run_rofi_task_submenu(store: PlanStore, key: str) -> None:
    row = store.get_task(key)
    if row is None:
        return
    est = int(row["estimate_min"] or store.cfg.default_estimate_minutes)
    actions = [
        ("focus", f"󰓾  Start Focus Session ({est}m · auto-DND)"),
        ("done", "󰄬  Mark Done"),
        ("steps", "󰉻  Decompose into timed steps…"),
        ("snooze_15", "󰅐  Snooze +15m"),
        ("snooze_tmr", "󰖛  Defer to Tomorrow 09:00"),
        ("delete", "󰧧  Delete Task"),
    ]
    rc, idx, _, _ = _rofi_prompt(
        str(row["title"])[:32],
        [a[1] for a in actions],
        mesg=f"<b>{html.escape(str(row['title']))}</b>  •  Project: {html.escape(str(row['project_name']))}",
        theme_str=ROFI_THEME_SUB,
    )
    if rc != 0 or idx < 0 or idx >= len(actions):
        return
    act = actions[idx][0]
    now = now_local(store.cfg)
    if act == "focus":
        focus_start(store, key, now)
    elif act == "done":
        store.mark_task_done(key, now, done=True)
        write_lock_status(store, now)
        show_osd(f"Done: {row['title']}")
        opportunistic_background_sync(store.cfg)
    elif act == "steps":
        _prompt_decompose_steps(store, key, str(row["title"]))
    elif act == "snooze_15":
        store.snooze_task(key, now + dt.timedelta(minutes=15), now)
        write_lock_status(store, now)
        show_osd(f"Snoozed +15m: {row['title']}")
        opportunistic_background_sync(store.cfg)
    elif act == "snooze_tmr":
        tmr = (now + dt.timedelta(days=1)).replace(hour=9, minute=0, second=0, microsecond=0)
        store.snooze_task(key, tmr, now)
        write_lock_status(store, now)
        show_osd(f"Deferred to tomorrow: {row['title']}")
        opportunistic_background_sync(store.cfg)
    elif act == "delete":
        store.delete_item(key, now)
        write_lock_status(store, now)
        show_osd(f"Deleted: {row['title']}")
        opportunistic_background_sync(store.cfg)


def _run_rofi_event_submenu(store: PlanStore, uid: str) -> None:
    actions = [("delete", "󰧧  Delete Calendar Event")]
    rc, idx, _, _ = _rofi_prompt("Event", [a[1] for a in actions], theme_str=ROFI_THEME_SUB)
    if rc == 0 and idx == 0:
        now = now_local(store.cfg)
        store.delete_item(uid, now)
        write_lock_status(store, now)
        show_osd("Deleted event")
        opportunistic_background_sync(store.cfg)


def commit_day_plan(store: PlanStore, plan: DayPlan, now: dt.datetime) -> int:
    stamp = to_utc_iso(now) or ""
    bounds: dict[str, tuple[dt.datetime, dt.datetime]] = {}
    for blk in plan.slotted:
        if blk.key not in bounds:
            bounds[blk.key] = (blk.start, blk.end)
        else:
            first_s, last_e = bounds[blk.key]
            bounds[blk.key] = (min(first_s, blk.start), max(last_e, blk.end))
    for key, (first_s, last_e) in bounds.items():
        store.conn.execute(
            """
            UPDATE tasks
               SET start_at = ?,
                   end_at = ?,
                   auto_slotted = 1,
                   dirty_op = 'upsert',
                   updated_at = ?
             WHERE local_key = ?
            """,
            (to_utc_iso(first_s), to_utc_iso(last_e), stamp, key),
        )

    # Clear stale windows on undone auto-slotted tasks from today that were bumped out
    prev_auto_rows = store.conn.execute(
        """
        SELECT local_key, start_at
          FROM tasks
         WHERE done = 0
           AND auto_slotted = 1
           AND start_at IS NOT NULL
           AND COALESCE(dirty_op, '') != 'delete'
        """
    ).fetchall()
    for row in prev_auto_rows:
        lkey = str(row["local_key"])
        if lkey in bounds:
            continue
        s_dt = from_iso(row["start_at"], store.cfg.tz)
        if s_dt is not None and s_dt.date() == plan.date:
            store.conn.execute(
                """
                UPDATE tasks
                   SET start_at = NULL,
                       end_at = NULL,
                       auto_slotted = 0,
                       dirty_op = 'upsert',
                       updated_at = ?
                 WHERE local_key = ?
                """,
                (stamp, lkey),
            )

    store.conn.commit()
    return len(bounds)


# ============================================================================
# Actionable Mako Notification Daemon
# ============================================================================


def _spawn_action_notification(
    cfg: PlanConfig,
    summary: str,
    body: str,
    urgency: str,
    actions: list[tuple[str, str]],
    on_action: Any,
    timeout_ms: int = 15000,
    invoke_on_dismiss: bool = False,
) -> None:
    notify_bin = shutil.which("notify-send")
    if not notify_bin:
        return

    def worker() -> None:
        cmd = [
            notify_bin,
            "-a",
            "junix-plan",
            "-u",
            urgency,
            "-t",
            str(timeout_ms),
            "--wait",
        ]
        for act_id, act_label in actions:
            cmd.append(f"--action={act_id}={act_label}")
        # Per FreeDesktop Notifications Spec, summary is plain text while body is Pango markup
        cmd.extend([summary, html.escape(body)])
        proc_timeout = None if timeout_ms == 0 else max(30, int(timeout_ms / 1000) + 30)
        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=proc_timeout,
                check=False,
            )
            chosen = proc.stdout.strip()
            if chosen:
                on_action(chosen)
            elif invoke_on_dismiss:
                on_action("dismiss")
        except Exception:
            if invoke_on_dismiss:
                on_action("dismiss")

    threading.Thread(target=worker, daemon=True).start()


def daemon_tick(store: PlanStore, now: dt.datetime) -> list[tuple[str, str, str]]:
    """Evaluate due events, due tasks, and active focus timers; return fired alerts for testing."""
    local_now = now.astimezone(store.cfg.tz)
    prune_cutoff = to_utc_iso(local_now - dt.timedelta(days=14)) or ""
    if prune_cutoff:
        store.conn.execute(
            "DELETE FROM notified WHERE fired_at != '' AND fired_at < ?",
            (prune_cutoff,),
        )
        store.conn.commit()
    plan = compute_day_plan(store, local_now)
    fired: list[tuple[str, str, str]] = []

    def mark_fired(dedup_key: str) -> bool:
        row = store.conn.execute(
            "SELECT 1 FROM notified WHERE dedup_key = ?", (dedup_key,)
        ).fetchone()
        if row is not None:
            return False
        store.conn.execute(
            "INSERT INTO notified (dedup_key, fired_at) VALUES (?, ?)",
            (dedup_key, to_utc_iso(local_now) or ""),
        )
        store.conn.commit()
        return True

    # 1. Hard appointment alerts (urgency=critical pierces Mako DND!)
    for ev in plan.appointments:
        if ev.kind != "event":
            continue
        mins_until = (ev.start - local_now).total_seconds() / 60.0
        for lead, tag in ((15, "15m"), (0, "now")):
            if (lead - 1.5) <= mins_until <= (lead + 0.5):
                dkey = f"ev:{ev.key}:{ev.start.isoformat()}:{tag}"
                if mark_fired(dkey):
                    title = (
                        f"Appointment Now: {ev.title}"
                        if lead == 0
                        else f"In 15m: {ev.title} ({ev.start:%H:%M})"
                    )
                    body = ev.subtitle or f"{ev.start:%H:%M}–{ev.end:%H:%M}"
                    fired.append(("critical", title, body))
                    _spawn_action_notification(
                        store.cfg,
                        title,
                        body,
                        urgency="critical",
                        actions=[("ack", "Got it")],
                        on_action=lambda _c: None,
                        timeout_ms=0,
                    )

    # 2. Due task reminders (normal urgency respects DND, with clickable Done / Focus / +15m!)
    all_rows = store.active_tasks()
    active_by_key = {r["local_key"]: r for r in all_rows}
    undone_steps_by_parent: dict[str, list[sqlite3.Row]] = {}
    for r in all_rows:
        pk = r["parent_key"]
        if pk and pk in active_by_key and not r["done"]:
            undone_steps_by_parent.setdefault(pk, []).append(r)
    for kids in undone_steps_by_parent.values():
        kids.sort(key=lambda x: (x["step_index"] or 999, x["updated_at"]))

    for row in all_rows:
        if row["done"]:
            continue
        # Skip parent container tasks while child steps remain undone, and only alert
        # on the current actionable (first undone) step of any parent.
        if row["local_key"] in undone_steps_by_parent:
            continue
        if row["parent_key"] and row["parent_key"] in undone_steps_by_parent:
            first_open = undone_steps_by_parent[row["parent_key"]][0]
            if first_open["local_key"] != row["local_key"]:
                continue
        due_dt = from_iso(row["due_at"], store.cfg.tz)
        if due_dt is None:
            continue
        snoozed = from_iso(row["snoozed_until"], store.cfg.tz)
        effective_due = max(due_dt, snoozed) if snoozed else due_dt
        diff_min = (effective_due - local_now).total_seconds() / 60.0
        if -30.0 <= diff_min <= 0.5:
            tkey = str(row["local_key"])
            dkey = f"task:{tkey}:{effective_due.isoformat()}"
            if mark_fired(dkey):
                title = f"Due: {row['title']}"
                est = int(row["estimate_min"] or store.cfg.default_estimate_minutes)
                body = f"{row['project_name']}  •  ~{est}m"
                fired.append(("normal", title, body))

                def handle_task_action(choice: str, target_key: str = tkey) -> None:
                    sub_store = PlanStore(store.cfg)
                    try:
                        ts = now_local(store.cfg)
                        if choice == "done":
                            sub_store.mark_task_done(target_key, ts, done=True)
                            write_lock_status(sub_store, ts)
                            opportunistic_background_sync(store.cfg)
                        elif choice == "focus":
                            focus_start(sub_store, target_key, ts)
                        elif choice == "snooze":
                            sub_store.snooze_task(
                                target_key, ts + dt.timedelta(minutes=15), ts
                            )
                            write_lock_status(sub_store, ts)
                            opportunistic_background_sync(store.cfg)
                    finally:
                        sub_store.close()

                _spawn_action_notification(
                    store.cfg,
                    title,
                    body,
                    urgency="normal",
                    actions=[
                        ("done", "✓ Done"),
                        ("focus", "▶ Focus"),
                        ("snooze", "+15m"),
                    ],
                    on_action=handle_task_action,
                    timeout_ms=20000,
                )

    # 3. Focus session completion check (release owned DND so completion prompt is visible!)
    focus = store.get_focus()
    if focus["active"] and not focus["completed_prompted"]:
        ends_at = from_iso(focus["ends_at"], store.cfg.tz)
        if ends_at is not None and local_now >= ends_at:
            if focus["dnd_owned"]:
                set_mako_dnd(False)
            store.conn.execute(
                "UPDATE focus SET dnd_owned = 0, completed_prompted = 1 WHERE singleton = 1"
            )
            store.conn.commit()
            expected_task_key = focus["task_key"]
            expected_started_at = focus["started_at"]
            expected_ends_at = focus["ends_at"]
            ftitle = str(focus["title"])
            fired.append(("normal", f"Focus complete: {ftitle}", "Mark step done or extend?"))

            def handle_focus_end(choice: str) -> None:
                sub_store = PlanStore(store.cfg)
                try:
                    cur_foc = sub_store.get_focus()
                    if (
                        not cur_foc["active"]
                        or not cur_foc["completed_prompted"]
                        or cur_foc["task_key"] != expected_task_key
                        or cur_foc["started_at"] != expected_started_at
                        or cur_foc["ends_at"] != expected_ends_at
                    ):
                        return
                    ts = now_local(store.cfg)
                    if choice == "done":
                        t_key = cur_foc["task_key"]
                        t_row = sub_store.get_task(str(t_key)) if t_key else None
                        nxt = sub_store.next_sibling_step(t_row) if t_row is not None else None
                        focus_stop(
                            sub_store,
                            ts,
                            mark_done=True,
                            quiet_osd=(nxt is not None),
                        )
                        opportunistic_background_sync(store.cfg)
                        if nxt is not None:
                            focus_start(sub_store, str(nxt["local_key"]), ts)
                    elif choice == "extend":
                        focus_extend(sub_store, 10, ts)
                    else:
                        focus_stop(sub_store, ts, mark_done=False)
                finally:
                    sub_store.close()

            _spawn_action_notification(
                store.cfg,
                f"Focus complete: {ftitle}",
                "Step timer finished — complete & advance or extend?",
                urgency="normal",
                actions=[
                    ("done", "✓ Done & Next"),
                    ("extend", "+10m"),
                    ("stop", "Stop"),
                ],
                on_action=handle_focus_end,
                timeout_ms=0,
                invoke_on_dismiss=True,
            )

    write_lock_status(store, local_now)
    return fired


def run_daemon(cfg: PlanConfig) -> int:
    stop_event = threading.Event()

    def _sig_handler(_signum: int, _frame: Any) -> None:
        stop_event.set()

    signal.signal(signal.SIGINT, _sig_handler)
    signal.signal(signal.SIGTERM, _sig_handler)

    last_sync_mono: float | None = None
    prev_cred_sig: tuple[str, ...] | None = None
    while not stop_event.is_set():
        cfg = load_config()
        cred_sig = (
            (
                cfg.vikunja_url,
                cfg.vikunja_token,
                cfg.radicale_url,
                cfg.radicale_user,
                cfg.radicale_password,
            )
            if (cfg.has_vikunja_creds or cfg.has_radicale_creds)
            else None
        )
        if cred_sig is not None and cred_sig != prev_cred_sig:
            last_sync_mono = None
        prev_cred_sig = cred_sig

        now = now_local(cfg)
        mono = time.monotonic()
        store = PlanStore(cfg)
        try:
            if last_sync_mono is None or (mono - last_sync_mono) >= max(30, cfg.sync_interval_sec):
                sync_all(store, now)
                last_sync_mono = mono
            daemon_tick(store, now)
        except Exception as exc:
            print(f"junix-plan daemon warning: {exc}", file=sys.stderr, flush=True)
        finally:
            store.close()
        stop_event.wait(15.0)
    return 0


# ============================================================================
# CLI Entrypoint
# ============================================================================


def cmd_agenda(store: PlanStore, as_json: bool = False) -> int:
    now = now_local(store.cfg)
    plan = compute_day_plan(store, now)
    focus = store.get_focus()

    if as_json:
        payload = {
            "date": plan.date.isoformat(),
            "open_count": plan.open_count,
            "focus": dict(focus) if focus["active"] else None,
            "appointments": [
                {
                    "key": b.key,
                    "title": b.title,
                    "start": b.start.isoformat(),
                    "end": b.end.isoformat(),
                    "location": b.subtitle,
                }
                for b in plan.appointments
            ],
            "slotted": [
                {
                    "key": b.key,
                    "title": b.title,
                    "step": b.step_badge,
                    "start": b.start.isoformat(),
                    "end": b.end.isoformat(),
                    "note": b.partial_note,
                    "context": b.subtitle,
                }
                for b in plan.slotted
            ],
        }
        print(json.dumps(payload, indent=2))
        return 0

    print(f"=== Day Plan · {plan.date:%A, %d.%m.%Y} ({plan.open_count} open) ===")
    if focus["active"]:
        print(f"  [FOCUS] {focus['title']} (until {from_iso(focus['ends_at'], store.cfg.tz):%H:%M})")
    for ev in plan.all_day_events:
        print(f"  [ALL DAY] {ev.summary}")
    merged = sorted(
        plan.appointments + plan.slotted,
        key=lambda b: (b.start, 0 if b.kind == "event" else 1),
    )
    if not merged:
        print("  Schedule clear — no appointments or open tasks.")
    for b in merged:
        span = _format_block_span(b, plan.date, sep="-")
        if b.kind == "event":
            loc = f" @ {b.subtitle}" if b.subtitle else ""
            print(f"  {span}  [EVENT] {b.title}{loc}  ({b.key})")
        elif b.kind == "fixed_task":
            print(f"  {span}  [PINNED] {b.title} [{b.subtitle}]  ({b.key})")
        else:
            badge = f"{b.step_badge} " if b.step_badge else ""
            print(f"  {span}  [STEP]  {badge}{b.title} ({b.partial_note}) · {b.subtitle}  ({b.key})")
    if plan.unscheduled_tasks:
        print("\n  Backlog (beyond today's free windows):")
        for r in plan.unscheduled_tasks:
            print(f"    - {r['title']} [{r['project_name']}] ({r['local_key']})")
    return 0


def _add_dcal_caldav_account(
    dcal_exe: str,
    url: str,
    username: str,
    password: str,
    display_name: str,
    ca_cert: str = "",
) -> tuple[bool, str]:
    env = dict(os.environ)
    if ca_cert and "SSL_CERT_FILE" not in env and not Path("/etc/ssl/certs/ca-certificates.crt").is_file():
        env["SSL_CERT_FILE"] = ca_cert
    try:
        proc = subprocess.run(
            [
                dcal_exe,
                "account",
                "add",
                "caldav",
                "--url",
                url,
                "--username",
                username,
                "--name",
                display_name,
            ],
            input=f"{password}\n",
            capture_output=True,
            text=True,
            env=env,
            timeout=15.0,
            check=False,
        )
        if proc.returncode == 0:
            return True, ""
        detail = (proc.stderr or proc.stdout or "").strip()
        # Strip any echoed prompt prefix from readPassword when stdin is a pipe
        detail = re.sub(r"^Password:\s*", "", detail).strip()
        return False, detail or f"exit {proc.returncode}"
    except Exception as exc:
        return False, str(exc)


def _provision_dcal_accounts(cfg: PlanConfig) -> int:
    dcal_exe = shutil.which("dcal")
    if not dcal_exe:
        return 0
    rc = 0
    if cfg.has_radicale_creds:
        ok, err_msg = _add_dcal_caldav_account(
            dcal_exe,
            cfg.radicale_url,
            cfg.radicale_user,
            cfg.radicale_password,
            "Junix Calendar",
            ca_cert=cfg.ca_cert,
        )
        if ok:
            print(f"Dux Calendar OK: synced Radicale ({cfg.radicale_url})")
        else:
            print(f"warning: Dux Calendar Radicale setup failed ({err_msg})", file=sys.stderr)
            rc = 1
    if cfg.has_vikunja_creds:
        vk_dav_url = f"{cfg.vikunja_url.rstrip('/')}/dav/projects/"
        vk_user = cfg.radicale_user or getpass.getuser()
        ok, err_msg = _add_dcal_caldav_account(
            dcal_exe,
            vk_dav_url,
            vk_user,
            cfg.vikunja_token,
            "Junix Tasks",
            ca_cert=cfg.ca_cert,
        )
        if ok:
            print(f"Dux Calendar OK: synced Vikunja tasks ({vk_dav_url})")
        else:
            print(
                f"note: Dux Calendar Vikunja CalDAV skipped ({err_msg}); "
                "grant `caldav` scope on your Vikunja API token or create a CalDAV token "
                "under Settings -> CalDAV if you also want VTODO tasks inside Dux Calendar.",
                file=sys.stderr,
            )
    return rc


def cmd_auth(cfg: PlanConfig, args: argparse.Namespace) -> int:
    cred_path = cfg.config_dir / "credentials.env"
    if getattr(args, "dcal_only", False):
        reloaded = load_config()
        if not reloaded.has_radicale_creds and not reloaded.has_vikunja_creds:
            print(
                f"error: no saved credentials found in {cred_path}; run `plan auth` first.",
                file=sys.stderr,
            )
            return 1
        if not shutil.which("dcal"):
            print("error: `dcal` (Dux Calendar) is not installed on PATH.", file=sys.stderr)
            return 1
        return _provision_dcal_accounts(reloaded)

    existing_creds = load_env_file(cred_path)

    vk_token = (
        args.vikunja_token.strip()
        if args.vikunja_token is not None
        else getpass.getpass("Vikunja API Token (leave blank to skip): ").strip()
    )
    default_user = cfg.radicale_user or existing_creds.get("RADICALE_USER") or getpass.getuser()
    rad_user = (
        (args.radicale_user.strip() or default_user)
        if args.radicale_user is not None
        else (input(f"Radicale Username [{default_user}]: ").strip() or default_user)
    )
    rad_pass = (
        args.radicale_password.strip()
        if args.radicale_password is not None
        else getpass.getpass("Radicale Password (leave blank to skip): ").strip()
    )

    final_vk = vk_token or existing_creds.get("VIKUNJA_TOKEN", "")
    final_user = rad_user or existing_creds.get("RADICALE_USER", "")
    final_pass = rad_pass or existing_creds.get("RADICALE_PASSWORD", "")

    if cfg.credentials_file and Path(cfg.credentials_file).resolve() != cred_path.resolve():
        print(
            f"note: declarative credentialsFile ({cfg.credentials_file}) is configured; "
            f"writing interactive credentials to {cred_path} (overlaid by credentialsFile keys).",
            file=sys.stderr,
        )
    lines: list[str] = []
    if final_vk:
        lines.append(f"VIKUNJA_TOKEN={final_vk}")
    if final_user:
        lines.append(f"RADICALE_USER={final_user}")
    if final_pass:
        lines.append(f"RADICALE_PASSWORD={final_pass}")
    atomic_write(cred_path, ("\n".join(lines) + "\n") if lines else "", mode=0o600)
    print(f"Saved credentials to {cred_path} (0600).")

    reloaded = load_config()
    rc = 0
    if reloaded.has_vikunja_creds:
        try:
            projects = VikunjaClient(reloaded).list_projects()
            print(f"Vikunja OK: {len(projects)} project(s) accessible")
        except urllib.error.HTTPError as exc:
            print(
                f"error: Vikunja verification failed (HTTP {exc.code}): check token permissions "
                "(projects, tasks, task relations).",
                file=sys.stderr,
            )
            rc = 1
        except (urllib.error.URLError, OSError, ssl.SSLError) as exc:
            reason = getattr(exc, "reason", None) or exc
            print(
                f"error: Vikunja unreachable ({reason}); credentials remain saved at {cred_path}.",
                file=sys.stderr,
            )
            rc = 1
    if reloaded.has_radicale_creds:
        try:
            col = RadicaleClient(reloaded).ensure_calendar_collection()
            print(f"Radicale OK: calendar collection ready at {col}")
        except urllib.error.HTTPError as exc:
            print(
                f"error: Radicale verification failed (HTTP {exc.code}): check username/password.",
                file=sys.stderr,
            )
            rc = 1
        except (urllib.error.URLError, OSError, ssl.SSLError) as exc:
            reason = getattr(exc, "reason", None) or exc
            print(
                f"error: Radicale unreachable ({reason}); credentials remain saved at {cred_path}.",
                file=sys.stderr,
            )
            rc = 1
    if rc == 0:
        _provision_dcal_accounts(reloaded)
    return rc


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="plan",
        description="Junix Day Engine: offline-first tasks, CalDAV events, step auto-slotter, and Hyprland HUD",
    )
    sub = p.add_subparsers(dest="cmd")

    p_add = sub.add_parser("add", help="Quick-add a task (supports >> steps, ~30m, !high, #project)")
    p_add.add_argument("text", nargs="+", help="Task specification")

    p_ev = sub.add_parser("event", help="Add a CalDAV appointment (@Location, HH:MM-HH:MM, weekly)")
    p_ev.add_argument("text", nargs="+", help="Appointment specification")

    p_dec = sub.add_parser("decompose", help="Split an existing task into ordered timed steps")
    p_dec.add_argument("key", help="Parent task key")
    p_dec.add_argument("steps", nargs="+", help="Ordered steps (e.g. 'Outline ~20m' 'Draft ~45m')")

    p_imp = sub.add_parser("import-ics", help="Import VEVENT appointments from an .ics file")
    p_imp.add_argument("path", help="Path to .ics file")

    p_ag = sub.add_parser("agenda", help="Show today's time-aware schedule & auto-slotted steps")
    p_ag.add_argument("--json", action="store_true", help="Emit JSON output")
    p_ag.add_argument("--commit", action="store_true", help="Write slotted times back to Vikunja")

    p_done = sub.add_parser("done", help="Mark a task or step complete")
    p_done.add_argument("key", help="Task local_key or remote_id")

    p_snz = sub.add_parser("snooze", help="Snooze a task (+15m, +1h, tomorrow)")
    p_snz.add_argument("key", help="Task key")
    p_snz.add_argument("when", nargs="?", default="15m", help="Duration like 15m, 1h, or 'tomorrow'")

    p_del = sub.add_parser("delete", help="Delete a task or event")
    p_del.add_argument("key", help="Task key or event UID")

    p_foc = sub.add_parser("focus", help="Control Focus sessions (with automatic Mako DND)")
    fsub = p_foc.add_subparsers(dest="focus_cmd")
    f_start = fsub.add_parser("start", help="Start focusing on a task/step")
    f_start.add_argument("key", help="Task/step key")
    f_start.add_argument("--minutes", type=int, default=None, help="Override focus minutes")
    fsub.add_parser("complete", help="Mark focused step done and restore DND")
    fsub.add_parser("stop", help="Stop focus without marking done")
    f_ext = fsub.add_parser("extend", help="Extend active focus session")
    f_ext.add_argument("minutes", nargs="?", type=int, default=10)
    fsub.add_parser("status", help="Show current focus status")

    sub.add_parser("pulse", help="Show barless Hyprland notification HUD (bound to SUPER+T)")
    sub.add_parser("lock-status", help="Print cached single-line status for hyprlock")

    p_rofi = sub.add_parser("rofi", help="Open interactive Gruvbox Rofi Day Hub")
    p_rofi.add_argument("--capture", action="store_true", help="Open direct quick-capture input")

    p_sync = sub.add_parser("sync", help="Synchronize offline queue with Vikunja & Radicale")
    p_sync.add_argument("--quiet", action="store_true")

    p_auth = sub.add_parser("auth", help="Configure Vikunja token & Radicale credentials")
    p_auth.add_argument("--vikunja-token", default=None)
    p_auth.add_argument("--radicale-user", default=None)
    p_auth.add_argument("--radicale-password", default=None)
    p_auth.add_argument(
        "--dcal-only",
        action="store_true",
        help="Provision Dux Calendar CalDAV accounts from saved credentials without prompting",
    )

    sub.add_parser("daemon", help="Run background sync, reminder, and Focus DND daemon")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    cfg = load_config()
    cmd = args.cmd or "agenda"

    if cmd == "auth":
        return cmd_auth(cfg, args)
    if cmd == "daemon":
        return run_daemon(cfg)
    if cmd == "lock-status":
        if cfg.lock_status_path.is_file():
            txt = cfg.lock_status_path.read_text(encoding="utf-8").strip()
            if txt:
                print(txt)
                return 0
        store = PlanStore(cfg)
        try:
            print(write_lock_status(store, now_local(cfg)))
            return 0
        finally:
            store.close()

    store = PlanStore(cfg)
    try:
        now = now_local(cfg)
        if cmd == "add":
            cap = parse_quick_capture(
                " ".join(args.text),
                now,
                default_kind="task",
                default_project=cfg.default_project,
                default_estimate_minutes=cfg.default_estimate_minutes,
            )
            if cap.kind == "event":
                uid = store.add_captured_event(cap, now)
                write_lock_status(store, now)
                opportunistic_background_sync(cfg)
                print(f"Added event {uid}: {cap.title} ({cap.start_at:%Y-%m-%d %H:%M})")
                return 0
            key = store.add_captured_task(cap, now)
            write_lock_status(store, now)
            opportunistic_background_sync(cfg)
            steps_info = f" with {len(cap.steps)} step(s)" if cap.steps else ""
            print(f"Added task {key}: {cap.title}{steps_info}")
            return 0
        if cmd == "event":
            cap = parse_quick_capture(
                " ".join(args.text),
                now,
                default_kind="event",
                default_project=cfg.default_project,
                default_estimate_minutes=cfg.default_estimate_minutes,
            )
            uid = store.add_captured_event(cap, now)
            write_lock_status(store, now)
            opportunistic_background_sync(cfg)
            print(f"Added event {uid}: {cap.title} ({cap.start_at:%Y-%m-%d %H:%M})")
            return 0
        if cmd == "decompose":
            try:
                keys = store.decompose_task(args.key, args.steps, now)
            except KeyError:
                print(f"Task not found: {args.key}", file=sys.stderr)
                return 1
            write_lock_status(store, now)
            opportunistic_background_sync(cfg)
            print(f"Created {len(keys)} step(s): {', '.join(keys)}")
            return 0
        if cmd == "import-ics":
            raw = Path(args.path).read_text(encoding="utf-8")
            n = store.import_ics_text(raw, now)
            write_lock_status(store, now)
            opportunistic_background_sync(cfg)
            print(f"Imported {n} event(s).")
            return 0
        if cmd == "agenda":
            if args.commit:
                plan = compute_day_plan(store, now)
                n = commit_day_plan(store, plan, now)
                opportunistic_background_sync(cfg)
                print(f"Committed {n} auto-slotted block(s) to Vikunja.")
            return cmd_agenda(store, as_json=args.json)
        if cmd == "done":
            updated = store.mark_task_done(args.key, now, done=True)
            if updated is None:
                print(f"Task not found: {args.key}", file=sys.stderr)
                return 1
            write_lock_status(store, now)
            opportunistic_background_sync(cfg)
            print(f"Completed: {updated['title']}")
            return 0
        if cmd == "snooze":
            if args.when.lower() in ("tomorrow", "morgen"):
                until = (now + dt.timedelta(days=1)).replace(
                    hour=9, minute=0, second=0, microsecond=0
                )
            else:
                mins = parse_duration_token(args.when.lstrip("+"), require_tilde=False) or 15
                until = now + dt.timedelta(minutes=mins)
            updated = store.snooze_task(args.key, until, now)
            if updated is None:
                print(f"Task not found: {args.key}", file=sys.stderr)
                return 1
            write_lock_status(store, now)
            opportunistic_background_sync(cfg)
            print(f"Snoozed {updated['title']} until {until:%Y-%m-%d %H:%M}")
            return 0
        if cmd == "delete":
            if not store.delete_item(args.key, now):
                print(f"Item not found: {args.key}", file=sys.stderr)
                return 1
            write_lock_status(store, now)
            opportunistic_background_sync(cfg)
            print(f"Deleted {args.key}")
            return 0
        if cmd == "focus":
            fcmd = args.focus_cmd or "status"
            if fcmd == "start":
                try:
                    print(focus_start(store, args.key, now, override_minutes=args.minutes))
                except KeyError:
                    print(f"Task not found: {args.key}", file=sys.stderr)
                    return 1
                return 0
            if fcmd == "complete":
                print(focus_stop(store, now, mark_done=True))
                opportunistic_background_sync(cfg)
                return 0
            if fcmd == "stop":
                print(focus_stop(store, now, mark_done=False))
                return 0
            if fcmd == "extend":
                print(focus_extend(store, args.minutes, now))
                return 0
            cur = store.get_focus()
            if not cur["active"]:
                print("Idle (no active focus session)")
            else:
                e_at = from_iso(cur["ends_at"], cfg.tz) or now
                rem = max(0, int(round((e_at - now).total_seconds() / 60.0)))
                print(f"Focusing: {cur['title']} ({rem}m remaining)")
            return 0
        if cmd == "pulse":
            header, body = build_pulse_summary(store, now)
            rc, _ = _run_quiet(["notify-send", "-a", "notify-send", "-t", "4500", header, body])
            if rc != 0:
                print(f"{header}\n{body}")
            return 0
        if cmd == "rofi":
            if args.capture:
                return run_rofi_capture_only(store)
            return run_rofi_hub(store)
        if cmd == "sync":
            res = sync_all(store, now)
            if not args.quiet:
                print(json.dumps(res, indent=2))
            return 1 if res["errors"] else 0
    finally:
        store.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
