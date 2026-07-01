---
description: One-time project bootstrap — populate the specs, invariants, and decision policy
agent: planner
subtask: false
---

You are running the **one-time Harness bootstrap**, NOT a normal planning cycle.
Ignore your usual rules and do not emit RESULT markers. Your job is to bring the
freshly-installed Harness to life by filling it with knowledge of THIS project —
including the two things that make full autonomy safe: the **invariants** and the
**decision policy**.

Current project signals:
- The constitution: @AGENTS.md
- Product seed: @.harness/specs/PRODUCT.md
- Architecture seed: @.harness/specs/ARCHITECTURE.md
- Decision policy: @.harness/specs/DECISION_POLICY.md

Do the following, asking the human concise questions whenever a fact is missing
rather than guessing:

1. **Interview briefly.** What the product is for, who uses it, the near-term goal,
   hard constraints — and crucially, what must NEVER happen (for invariants).

2. **Populate `.harness/specs/PRODUCT.md`** — the product in the user's terms. The
   only project context `desk` ever sees. (The runtime refuses to start without it.)

3. **Populate `.harness/specs/ARCHITECTURE.md`**, including the **INVARIANTS**
   section — the small set of absolute, non-negotiable rules (e.g. "never DELETE
   without soft-delete", "all data reads go through the API"). This is the most
   important part: invariants are the only veto the autonomous loop cannot override,
   so they are what keep it from doing something irreversible. Read existing code
   via `explore`; describe what exists, do not invent.

4. **Tune `.harness/specs/DECISION_POLICY.md`** — the WSJF weights and any priority
   rules (e.g. "production bugs weigh 3x a new feature"). This is the ONE place the
   human's judgment enters structurally; after this the loop prioritizes on its own.

5. **Seed `.harness/specs/ROADMAP.md`** with the first `## [pending]` items. Leave
   `SPRINT.md` empty — `planner` fills it.

6. **Generate the core skills** under `.harness/skills/` via the `skill-creator`
   skill (one or two; `distill` grows more later).

7. **Verify the runtime is live.** Run `bash .harness/runtime/state.sh counters`,
   `bash .harness/runtime/decide.sh wsjf 5 3 2 4`, and `bash .harness/dashboard.sh`;
   report what they print.

8. **Announce readiness.** Next step: `bash .harness/loop.sh` for the first cycle
   (or the Textual TUI), and `opencode --agent desk` to dump intake into the inbox.

Commit your work with a clear message (e.g. "harness: bootstrap project specs").
