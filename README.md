# **Opencode** Loop Harness 

This repository is a Ralph loop method with two loops (conversational Half Loop + autonomous Main Loop) man-in-the-loop, a **Decision Engine**. CoALA memory, quality gates, and a Presentation Layer (a Textual TUI with a Decision Log, plus a static HTML dashboard method).

Two loops that meet only through the inbox, and after intake:

```
  Half Loop                                     Main Loop
  ───────────────────────────────────          ───────────────────────────────
  you ─► desk ─► inbox.md ─► groom ─► plan ─► build ─► review ─► distill
                              (WSJF)  (decide) (code)  (gates)   (skills/MCP)
```

More details:
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`INSTALL.md`](INSTALL.md)
- [`docs/INSTALLER-DESIGN.md`](docs/INSTALLER-DESIGN.md)

---

## **Prompt to install**

```
Install the Ralph loop Harness (an autonomous-development runtime [github.com/pobruno/opencode-harness-loop]) into THIS project. Read this file in full and follow it end to end as the single source of truth:
https://raw.githubusercontent.com/pobruno/opencode-harness-loop/main/INSTALL.md
Don't skip phases. Stop and ask before any destructive action.
```

> That is the whole prompt, a single instruction. [`INSTALL.md`](INSTALL.md) is the complete playbook ("the brain").

---

- **desk** is the only agent you talk to. It structures your input and files it into the inbox.
- The **Decision Engine** makes all routine development decisions—prioritization, planning, decomposition, conflict resolution, and risk assessment.
- **Architecture invariants** define the only non-negotiable constraints; quality gates keep the implementation correct.
- Only tasks blocked by real external dependencies are parked. Everything else keeps moving.
- Every decision is recorded and visible through the live **Decision Log** and the HTML dashboard.

Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full design.

---

## Daily usage

```bash
opencode --agent desk                         # Add new work
bash .harness/loop.sh                         # Run the runtime
python .harness/presentation/textual/app.py   # Open the TUI
bash .harness/dashboard.sh                    # Generate dashboard
```

Useful commands:
```
/status
/consistency
/bootstrap
```

---

## Repository layout

```
opencode-harness-loop/
├── README.md                  # you are here — entry point + install prompt
├── INSTALL.md                 # the agent install playbook (single source of truth)
├── docs/
│   ├── ARCHITECTURE.md        # the definitive design (Autonomous Decision Doctrine)
│   └── INSTALLER-DESIGN.md    # why the installer works the way it does
└── template/                  # everything copied/generated into your project
    ├── .harness/  .opencode/  opencode.json
    └── _seed/                 # moulds the installer fills by reading your code
```

## What ends up installed

```
your-project/
├── AGENTS.md                 # the constitution (generated from your project)
├── opencode.json             # base config (merged, not clobbered)
└── .harness/                 # the whole runtime, self-contained
    ├── loop.sh  dashboard.sh # friendly entrypoints
    ├── runtime/              # scheduler, cycle, state, events, gates, +decide/scoring/precedence
    ├── specs/                # PRODUCT, ARCHITECTURE (+INVARIANTS), ROADMAP, SPRINT, DECISION_POLICY
    ├── inbox/                # inbox.md (your dump) + triaged/
    ├── PARKED.md             # tasks stopped ONLY by a missing external resource
    ├── tasks/                # TASK-*.md
    ├── memory/               # decisions, assumptions, learnings, patterns, intent, history/ (CoALA)
    ├── events/  state/        # the bus + runtime.json/understanding.json
    ├── skills/  mcp/          # procedural memory (grown by distill)
    └── presentation/         # textual/ TUI (+ Decision Log) + html/ static dashboard
```

Agents live in `.opencode/agent/` (opencode-native); skills under
`.harness/skills/` are registered via `opencode.json`.
