# The Ralph Harness installer — design and mechanics

> **The shift in perspective.** The "product" is not what the Harness builds; the
> product is **the Harness runtime itself and the ease of installing it** into any
> project — new or existing. The GitHub template does not deliver an application;
> it delivers an autonomous-development runtime plus an **install playbook** that
> an agent executes. You open OpenCode in your project, paste a short prompt, and
> the agent clones the template, installs the pieces, **adapts** what must be
> adapted, configures the MCPs, validates, and deletes the clone. The runtime
> stays; the clone disappears.

---

## 1. The central principle: three classes of file

Every file in the template falls into one of three classes, and each gets a
different treatment.

**FIXED — copied as-is.** The runtime and machinery that do not depend on the
project: all of `.harness/` (the `runtime/` bash, the `presentation/` layer, the
`specs`/`inbox`/`memory` header files), the `.opencode/` agents and commands, and
`opencode.json`. Identical in any project. On conflict the installer merges rather
than blindly overwriting.

**SEED — generated from the project.** The project-specific knowledge the template
cannot bring ready: `AGENTS.md` (project root), `.harness/specs/PRODUCT.md`, and
`.harness/specs/ARCHITECTURE.md`. The template ships *seeds* with gaps, and the
installer fills them by **reading the project**. This is where the "neat mechanic"
lives: the instruction carries no project information, so the agent must discover
it and validate against disk.

**ADAPTABLE — merged with what already exists.** The special case where the target
**already has** a file the Harness also uses — typically an `AGENTS.md` the owner
wrote. The installer preserves the owner's content and adds, in clearly marked
blocks, the rules the Harness requires.

Mental rule: *same in any project → FIXED; describes your project → SEED; already
existed and the Harness also needs it → ADAPTABLE.*

---

## 2. Why `AGENTS.md` is generated, never copied

This is empirical, not aesthetic. A generic or auto-duplicated `AGENTS.md` makes
agents **worse** — it reduces success rates and inflates inference cost, because
the agent spends attention re-reading what it could infer from the code. What
helps are **curated, minimal, high-signal** files with only what the agent cannot
deduce: exact commands with flags, explicit write-scope contracts, git-safety, and
domain vocabulary.

Three consequences the installer respects: `AGENTS.md` is **generated from the
real project** (not stamped from a mould); it is kept **short** (~32 KiB ceiling,
signal over completeness); and it separates **"always / ask first / never"** as
direct commands, because autonomous agents obey written risks better than implicit
conventions.

---

## 3. The installer flow, phase by phase

Seven phases (0–7). Each exists for a reason, and several have a safety gate.

- **Phase 0 — Reconnaissance.** Understand what you are installing (a runtime, not
  a product), then recon the target: new or existing? git? already has the
  Harness? language and package manager? This decides everything after.
- **Phase 1 — Clone.** The template goes into `.harness-tmp/`, outside the project
  tree, depth 1. The clone is scaffolding.
- **Phase 2 — Install FIXED, with conflict detection.** Copy `.harness/`,
  `.opencode/`, and `opencode.json`; merge rather than overwrite; stop and ask on a
  semantic name collision.
- **Phase 3 — Generate SEED by reading the project.** Produce `AGENTS.md` from the
  recon; populate `.harness/specs/PRODUCT.md` and `ARCHITECTURE.md` from the real
  code (or leave the bootstrap questions for a new project).
- **Phase 4 — Configure MCPs.** Register the manifest's servers into `opencode.json`;
  never invent secrets (placeholder + `.env.example`); leave `on_demand` servers
  disabled.
- **Phase 5 — Validate.** Confirm the counters read, the runtime dry-runs to idle,
  the dashboard generates, `runtime.json` is valid JSON, and the gates list.
- **Phase 6 — Clean up.** Delete the clone; `.gitignore` the ephemeral artefacts
  (`.harness/state/`, `events/`, `logs/`, the generated `index.html`, `.env`).
- **Phase 7 — Report.** Summarise copied / generated / merged / pending, and point
  at `/bootstrap` then `bash .harness/loop.sh` (or the TUI).

---

## 4. Where everything lives in the template repository

```
opencode-harness-loop/               (the repository on GitHub)
├── README.md                        # SHORT. What it is + the one-line prompt you paste.
├── INSTALL.md                       # The full PLAYBOOK the agent follows ("the brain").
├── docs/
│   ├── ARCHITECTURE.md              # The definitive v3 runtime design.
│   └── INSTALLER-DESIGN.md          # This document.
│
└── template/                        # everything that goes to the target project
    ├── opencode.json                #   FIXED — base config (merged on install)
    ├── .opencode/                   #   FIXED — the 6 agents + commands
    │   ├── agent/                   #     desk, groom, plan, build, review, distill
    │   └── command/                 #     bootstrap, status, consistency
    ├── .harness/                    #   FIXED — the whole runtime
    │   ├── loop.sh  dashboard.sh
    │   ├── runtime/                 #     scheduler, cycle, state, events, gates + decide/scoring/precedence (Decision Engine)
    │   ├── specs/                   #     ROADMAP/SPRINT/DECISION_POLICY headers (PRODUCT/ARCHITECTURE are SEED)
    │   ├── inbox/  memory/  PARKED.md   #   header files (the runtime fills them)
    │   ├── skills/                  #     skill-creator, mcp-synth (registered via opencode.json)
    │   ├── mcp/manifest.json        #     the list of MCPs the agent configures
    │   └── presentation/            #     textual/ TUI (+ Decision Log) + html/ static dashboard
    └── _seed/                       #   SEEDS — become adapted files at install
        ├── AGENTS.seed.md
        ├── PRODUCT.seed.md
        └── ARCHITECTURE.seed.md     #   (includes the INVARIANTS section)
```

`README.md` is the human entry point and contains **the one-line prompt** you
copy. That prompt is not the playbook — it points the agent at `INSTALL.md` as the
single source of truth and tells it to follow it end to end. The playbook itself
(Phase 1) performs the clone, so the pasted prompt never carries install logic and
never goes stale.

---

## 5. The fine points

- **Real idempotence.** Running the installer twice — or on a partially-installed
  project — must not break anything. Each step checks state, copies only what is
  missing, merges instead of overwriting, and detects "already installed".
- **Confirmation gates on destructive actions.** Overwriting, deleting, or touching
  `.git` stops and asks.
- **Secrets are never invented.** Placeholder + pending item, never a fabricated
  value.
- **Git-safety written as law.** The generated `AGENTS.md` declares the runtime's
  rules: the runtime owns commit/rollback, `build` never commits, never force-push,
  never commit `state/`/`events/`/`logs/` or secrets.
- **Stack detection drives the gates.** What Phase 0 discovers determines the
  commands in `AGENTS.md` and `.harness/gates.local.sh`.
- **The clone is scaffolding, not a dependency.** After Phase 6, no submodule, no
  source reference, no orphan folder — only the installed files.

---

## 6. The complete lifecycle, in one sentence

You open OpenCode in your project → paste the one-line prompt from the `README` →
the agent fetches `INSTALL.md`, recons the project, clones the template, copies the
fixed runtime, **generates `AGENTS.md` and the specs by reading your code**,
configures the MCPs with placeholders, validates that everything comes up, deletes
the clone, and hands you a report → you fill the credentials and run `/bootstrap` →
the Harness is installed and ready for the first cycle (headless via
`bash .harness/loop.sh`, or through the Textual TUI).
