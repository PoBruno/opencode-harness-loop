from textual.widgets import Static

_LOOPS = ["desk", "groom", "plan", "build", "review", "distill"]


class AgentsPanel(Static):
    """Lists the loops and marks the active one."""

    def update_data(self, state: dict) -> None:
        active = state.get("active_loop", "")
        lines = ["[b]Agents[/]"]
        for name in _LOOPS:
            if name == active:
                lines.append(f"[green]\u25cf[/] [b]{name}[/]  [green]running[/]")
            else:
                lines.append(f"[grey50]\u25cb[/] [grey62]{name}[/]")
        self.update("\n".join(lines))
