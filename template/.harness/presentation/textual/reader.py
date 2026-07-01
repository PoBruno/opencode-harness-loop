"""Read-only access to runtime state, counters, events, parked items, decisions.

The Presentation Layer is a pure consumer of state/ + events/. The only write
action anywhere in the TUI is launching the runtime (see app.py); everything
here is read-only.
"""

from __future__ import annotations

import json
import os
import re
from datetime import date


def harness_dir() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _p(*parts: str) -> str:
    return os.path.join(harness_dir(), *parts)


def read_runtime() -> dict:
    try:
        with open(_p("state", "runtime.json"), encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def runtime_alive(state: dict) -> bool:
    pid = state.get("pid", 0) or 0
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _count(pattern: str, path: str) -> int:
    try:
        with open(path, encoding="utf-8") as fh:
            return len(re.findall(pattern, fh.read(), re.MULTILINE))
    except OSError:
        return 0


def counters() -> dict:
    return {
        "inbox_pending": _count(r"^##\s+\[I-", _p("inbox", "inbox.md")),
        "parked": _count(r"^##\s+\S", _p("PARKED.md")),
        "sprint_open": _count(r"^\s*-\s+\[ \]", _p("specs", "SPRINT.md")),
        "sprint_done": _count(r"^\s*-\s+\[[xX]\]", _p("specs", "SPRINT.md")),
        "sprint_parked": _count(r"^\s*-\s+\[[pP]\]", _p("specs", "SPRINT.md")),
        "sprint_escalated": _count(r"^\s*-\s+\[!\]", _p("specs", "SPRINT.md")),
        "roadmap_pending": _count(r"^##\s+\[pending\]", _p("specs", "ROADMAP.md")),
        "roadmap_done": _count(r"^##\s+\[done\]", _p("specs", "ROADMAP.md")),
        "roadmap_rejected": _count(r"^##\s+\[auto-rejected\]", _p("specs", "ROADMAP.md")),
    }


def parked_items() -> list[str]:
    """Parked headings, each annotated with its reason line when present."""
    path = _p("PARKED.md")
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return []
    out: list[str] = []
    blocks = re.split(r"^##\s+", text, flags=re.MULTILINE)[1:]
    for b in blocks:
        title = b.splitlines()[0].strip() if b.strip() else ""
        m = re.search(r"^reason:\s*(.+)$", b, re.MULTILINE)
        out.append(f"{title} ({m.group(1).strip()})" if m else title)
    return out


def recent_decisions(limit: int = 30) -> list[dict]:
    """Recent decision.* / task.(parked|unparked|decomposed) events, newest first."""
    events, _ = read_new_events(0)
    out = [
        e for e in events
        if str(e.get("event", "")).startswith("decision.")
        or e.get("event") in ("task.parked", "task.unparked", "task.decomposed")
    ]
    return out[-limit:][::-1]


def events_path() -> str:
    return _p("events", f"{date.today().isoformat()}.jsonl")


def read_new_events(offset: int) -> tuple[list[dict], int]:
    """Return (new events since byte offset, new offset). Resets on day rollover."""
    path = events_path()
    events: list[dict] = []
    try:
        size = os.path.getsize(path)
    except OSError:
        return events, 0
    if offset > size:  # file rotated/truncated
        offset = 0
    try:
        with open(path, encoding="utf-8") as fh:
            fh.seek(offset)
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except ValueError:
                    continue
            offset = fh.tell()
    except OSError:
        pass
    return events, offset
