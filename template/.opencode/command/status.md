---
description: Show the current Harness runtime status and recent autonomous decisions
agent: desk
---

Runtime state:
!`jq . .harness/state/runtime.json 2>/dev/null || echo "(no state yet — the runtime has not run)"`

Counters (phase-decision inputs):
!`bash .harness/runtime/state.sh counters 2>/dev/null || echo "(could not read documents)"`

Recent events:
!`tail -n 10 ".harness/events/$(date +%F).jsonl" 2>/dev/null || echo "(no events today)"`

Recent autonomous decisions:
!`tail -n 40 ".harness/events/$(date +%F).jsonl" 2>/dev/null | grep -E '"event":"(decision|task\.(parked|unparked|decomposed))' | tail -8 || echo "(none)"`

Parked (waiting on an external resource):
!`grep -A2 '^## ' .harness/PARKED.md 2>/dev/null | grep -v '^<!--' || echo "(nothing parked)"`

Summarise the runtime status in 3–5 lines: health and what the active loop is
doing, sprint progress, what it decided on its own recently (reinterpreted /
auto-rejected / assumptions), and whether anything is parked. Do not change any
files.
