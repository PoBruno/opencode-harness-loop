from textual.widgets import Static


class ParkedPanel(Static):
    """Items parked on a missing external resource (never a decision)."""

    def update_data(self, items: list[str]) -> None:
        if not items:
            self.update("[b]Parked[/]\n[grey50]nothing waiting on a resource[/]")
            return
        body = "\n".join(f"[yellow]\u2022[/] {i}" for i in items[:5])
        more = f"\n[grey50]+{len(items) - 5} more[/]" if len(items) > 5 else ""
        self.update(f"[b]Parked[/] [yellow]{len(items)}[/]\n{body}{more}")
