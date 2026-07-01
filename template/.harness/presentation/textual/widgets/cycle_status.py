from textual.widgets import Static

_HEALTH = {"green": "green", "yellow": "yellow", "red": "red"}


class CycleStatus(Static):
    """Header card: cycle number, health, and liveness."""

    def update_data(self, state: dict) -> None:
        cycle = state.get("cycle", "-")
        health = state.get("health", "-")
        color = _HEALTH.get(health, "white")
        live = "[green]\u25cf live[/]" if state.get("_alive") else "[grey50]\u25cb idle[/]"
        msg = state.get("message", "") or ""
        self.update(
            f"[b]cycle[/] {cycle}    [b]health[/] [{color}]{health}[/]    {live}\n"
            f"[grey62]{msg}[/]"
        )
