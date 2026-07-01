#!/usr/bin/env python3
"""Ralph Harness — Textual TUI.

Local, day-to-day interface. It is a read-only consumer of state/ + events/,
with one controlled exception (section 14.1.1 of the architecture): it can
LAUNCH the runtime. It never writes state and never edits files.

  - On mount, if the runtime is not running, it starts `loop.sh --daemon`
    (detached, so closing the TUI does not kill the runtime).
  - It polls state/runtime.json and tails events/*.jsonl every 500 ms, showing
    live, scrollable event cards.

Keys:  r run loop   x stop loop   d Decision Log   g gen dashboard   q quit

Run:   python .harness/presentation/textual/app.py   [--no-autostart]
"""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from textual.app import App, ComposeResult  # noqa: E402
from textual.containers import Horizontal, Vertical  # noqa: E402
from textual.widgets import Footer, Header  # noqa: E402

import reader  # noqa: E402
from widgets import AgentsPanel, CurrentTask, CycleStatus, DecisionLog, EventLog, ParkedPanel  # noqa: E402


class HarnessApp(App):
    CSS = """
    Screen { layout: vertical; }
    #body { height: 1fr; }
    #left { width: 38; border-right: solid $panel-darken-2; }
    #left > Static { border: round $panel-darken-2; padding: 0 1; margin: 0 0 1 0; }
    #events { border: round $panel-darken-2; padding: 0 1; }
    #decisions { border: round $accent; padding: 1 2; margin: 2 6; height: 1fr; background: $panel; }
    """

    BINDINGS = [
        ("q", "quit", "Quit"),
        ("r", "run_loop", "Run loop"),
        ("x", "stop_loop", "Stop loop"),
        ("d", "decisions", "Decision Log"),
        ("g", "dashboard", "Gen dashboard"),
    ]

    def __init__(self, autostart: bool = True) -> None:
        super().__init__()
        self._offset = 0
        self._autostart = autostart

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal(id="body"):
            with Vertical(id="left"):
                yield CycleStatus(id="cyc")
                yield AgentsPanel(id="agents")
                yield CurrentTask(id="task")
                yield ParkedPanel(id="parked")
            yield EventLog(id="events", highlight=False, markup=True, wrap=True)
        yield Footer()

    def on_mount(self) -> None:
        self.title = "Ralph Harness"
        self.set_interval(0.5, self.refresh_state)
        self.refresh_state()
        if self._autostart and not self._alive():
            self.action_run_loop()

    # ---- read-only refresh -------------------------------------------------
    def _alive(self) -> bool:
        return reader.runtime_alive(reader.read_runtime())

    def refresh_state(self) -> None:
        state = reader.read_runtime()
        state["_alive"] = self._alive()
        counters = reader.counters()
        self.query_one("#cyc", CycleStatus).update_data(state)
        self.query_one("#agents", AgentsPanel).update_data(state)
        self.query_one("#task", CurrentTask).update_data(state, counters)
        self.query_one("#parked", ParkedPanel).update_data(reader.parked_items())
        events, self._offset = reader.read_new_events(self._offset)
        log = self.query_one("#events", EventLog)
        for ev in events:
            log.add_event(ev)

    # ---- the one write action: launching the runtime -----------------------
    def action_run_loop(self) -> None:
        if self._alive():
            self.notify("runtime already running")
            return
        hd = reader.harness_dir()
        project = os.path.dirname(hd)
        out_path = os.path.join(hd, "logs", "runtime.out")
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        out = open(out_path, "a", encoding="utf-8")
        subprocess.Popen(
            ["bash", os.path.join(hd, "loop.sh"), "--daemon"],
            cwd=project, stdout=out, stderr=out, start_new_session=True,
        )
        self.notify("started loop.sh --daemon")

    def action_stop_loop(self) -> None:
        pid = reader.read_runtime().get("pid", 0) or 0
        try:
            os.kill(int(pid), signal.SIGTERM)
            self.notify("sent stop signal to the runtime")
        except (OSError, ValueError, TypeError):
            self.notify("runtime is not running")

    def action_decisions(self) -> None:
        self.push_screen(DecisionLog())

    def action_dashboard(self) -> None:
        hd = reader.harness_dir()
        subprocess.Popen(
            ["bash", os.path.join(hd, "dashboard.sh")],
            cwd=os.path.dirname(hd),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.notify("regenerated dashboard/index.html")


def main() -> None:
    parser = argparse.ArgumentParser(description="Ralph Harness TUI")
    parser.add_argument("--no-autostart", action="store_true",
                        help="do not launch the runtime on open")
    args = parser.parse_args()
    HarnessApp(autostart=not args.no_autostart).run()


if __name__ == "__main__":
    main()
