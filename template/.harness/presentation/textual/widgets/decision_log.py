from textual.containers import Vertical
from textual.screen import ModalScreen
from textual.widgets import RichLog, Static

import reader


class DecisionLog(ModalScreen):
    """The screen that compensates for full autonomy: why the loop decided each
    thing. Reads decision.* / task.* events from the bus, newest first."""

    BINDINGS = [("escape", "close", "Close"), ("d", "close", "Close")]

    def compose(self):
        with Vertical(id="decisions"):
            yield Static("[b]Decision Log[/]   [grey50](esc / d to close)[/]")
            yield RichLog(id="dlog", markup=True, wrap=True, highlight=False)

    def on_mount(self) -> None:
        log = self.query_one("#dlog", RichLog)
        rows = reader.recent_decisions(80)
        if not rows:
            log.write("[grey50]no autonomous decisions recorded yet[/]")
            return
        for e in rows:
            ts = (e.get("ts", "") or "")[11:19]
            kind = str(e.get("event", "")).replace("decision.", "").replace("task.", "")
            task = e.get("task", "") or ""
            data = e.get("data", {})
            extra = ""
            if isinstance(data, dict) and data:
                extra = "  " + " ".join(f"{k}={v}" for k, v in data.items())
            log.write(f"[grey50]{ts}[/] [cyan]{kind}[/] [grey62]{task}[/]{extra}")

    def action_close(self) -> None:
        self.dismiss()
