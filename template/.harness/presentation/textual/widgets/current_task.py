from textual.widgets import Static


class CurrentTask(Static):
    """Shows the current task and sprint progress."""

    def update_data(self, state: dict, counters: dict) -> None:
        task = state.get("current_task") or "-"
        open_ = counters.get("sprint_open", 0)
        done = counters.get("sprint_done", 0)
        total = open_ + done
        pct = round(done / total * 100) if total else 0
        filled = pct // 5
        bar = "\u2588" * filled + "\u2591" * (20 - filled)
        last = state.get("last_review", "-")
        last_color = {"pass": "green", "fail": "red"}.get(last, "grey62")
        self.update(
            f"[b]Current Task[/]\n{task}\n"
            f"[cyan]{bar}[/] {pct}%\n"
            f"sprint {done}/{total}   last review: [{last_color}]{last}[/]"
        )
