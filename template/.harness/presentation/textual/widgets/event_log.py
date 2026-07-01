from textual.widgets import RichLog


def _event_color(ev: dict) -> str:
    name = ev.get("event", "")
    result = ev.get("result", "")
    if "fail" in name or ".red" in name or result == "fail":
        return "red"
    if ".yellow" in name:
        return "yellow"
    if "passed" in name or "finished" in name or result == "pass" or ".green" in name:
        return "green"
    return "white"


class EventLog(RichLog):
    """Scrollable, real-time feed of runtime events (the log 'cards')."""

    def add_event(self, ev: dict) -> None:
        ts = (ev.get("ts", "") or "")[11:19]
        name = ev.get("event", "")
        meta = " \u00b7 ".join(
            str(v) for v in (ev.get("loop"), ev.get("task"), ev.get("result")) if v
        )
        color = _event_color(ev)
        line = f"[grey50]{ts}[/] [{color}]{name}[/]"
        if meta:
            line += f"  [grey62]{meta}[/]"
        self.write(line)
