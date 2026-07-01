# Opencode Loop Harness

An autonomous-development **runtime** you drop into any project. You dump intake;
a Ralph loop (two loops, a Decision Engine, gates, on-disk memory) builds it,
and **never stops to ask you what to do**. It decides, records why, and keeps going.

## Install

Open OpenCode at your project root and paste:

```
Install the Opencode Loop Harness (an autonomous-development runtime, github.com/PoBruno/opencode-harness-loop) into THIS project. Read this file in full and follow it end to end as the single source of truth:
https://raw.githubusercontent.com/PoBruno/opencode-harness-loop/main/INSTALL.md
Don't skip phases. Stop and ask before any destructive action.
```

One instruction. [`INSTALL.md`](INSTALL.md) is the whole playbook ("the brain") —
the agent clones, recons your code, installs, generates the specs, and cleans up.

<!-- drop your TUI gif at docs/media/tui.gif -->
<p align="center">
  <img src="docs/media/tui.gif" alt="Harness TUI" width="820">
</p>

## How it works

```
  Half Loop (you dump, it never asks)      Main Loop (autonomous)
  ───────────────────────────────────      ──────────────────────
  you ─► desk ─► inbox.md ─► groom ─► planner ─► build ─► review ─► distill
                             (WSJF)  (decide) (code)  (gates)   (skills)
```

- **desk** is the only agent you talk to — it files your dump into the inbox.
- The **Decision Engine** resolves every ambiguity mechanically: WSJF priority,
  vertical-slice decomposition, precedence hierarchy, one-way/two-way doors,
  assumption logging. No `ask:`, ever.
- **Invariants** (you write once) are the only absolute veto; **gates** keep the
  code correct. A stall **escalates** to a fresh decision instead of halting.
- The only thing that ever waits on you is a missing external resource (an API
  key) → one task parks, the loop keeps flowing.
- Every decision is on the bus → live **Decision Log** (TUI) + static HTML dashboard.

Full design: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Daily use

One entrypoint — `.harness/run` (no extension; `chmod +x` once):

```bash
cd .harness
./run tui        # open the TUI (auto-creates the venv on first run)
./run daemon     # run the loop headless, waiting for new work (also: once | loop | stop)
./run desk       # dump work into the inbox (interactive; or: ./run desk "one message")
./run dashboard  # regenerate the static HTML dashboard
./run doctor     # check prerequisites · ./run help for everything
```

Inside OpenCode: `/status` · `/consistency` · `/audit` · `/bootstrap`.

## Requirements

Linux + Docker · `bash git jq coreutils` · `opencode` (authenticated). The TUI
also needs `python3`; `./run tui` builds its own venv (`python3-venv` if missing).

<details>
<summary>What gets installed</summary>

```
your-project/
├── AGENTS.md            # constitution (generated from your code)
├── opencode.json        # base config (merged, not clobbered)
└── .harness/
    ├── run              # single entrypoint (tui · daemon · desk · dashboard · doctor)
    ├── loop.sh  dashboard.sh
    ├── runtime/         # scheduler, cycle, state, events, gates + decide/scoring/precedence
    ├── specs/           # PRODUCT, ARCHITECTURE (+INVARIANTS), ROADMAP, SPRINT, DECISION_POLICY
    ├── inbox/  PARKED.md # your dump + the only human-facing wait
    ├── tasks/  memory/   # TASK-*.md + CoALA (decisions, assumptions, learnings, patterns, history)
    ├── events/  state/   # the bus + runtime.json / understanding.json
    ├── skills/  mcp/      # procedural memory (grown by distill)
    └── presentation/     # textual/ TUI (+ Decision Log) + html/ dashboard
```

Agents live in `.opencode/agent/`; skills under `.harness/skills/` (via `opencode.json`).
</details>

<details>
<summary>Repository layout</summary>

```
opencode-harness-loop/
├── README.md            # entry point + install prompt
├── INSTALL.md           # the agent install playbook (single source of truth)
├── docs/                # ARCHITECTURE.md, INSTALLER-DESIGN.md
└── template/            # everything copied/generated into your project (.harness/, .opencode/, _seed/)
```
</details>
