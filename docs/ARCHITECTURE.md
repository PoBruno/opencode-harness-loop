# The Harness — Master Architecture (Autonomous Decision Doctrine)

> Third version. It closes two gaps of the previous fusion: (1) the TUI was cited,
> not specified — here it has screens, widgets, keybinds, and a code skeleton; (2)
> the system still delegated decisions to the human via `ask:`/`BLOCKED.md`, which
> contradicts the product's goal. You do intake — a directive, feature, customer
> vision, bug, adjustment, modeling, whatever, with no required structure — and the
> loop never comes back to ask "what do I do now?". It decides, documents why, and
> keeps going.

> **opencode realization.** This document is executor-agnostic and describes the
> ideal tree with `spec/`, `memory/`, `INBOX.md`, etc. at the project root. In this
> repository the Harness runs on **opencode** and everything is kept self-contained
> under `.harness/` (so it installs cleanly into any project): `spec/` →
> `.harness/specs/`, `memory/` → `.harness/memory/`, `INBOX.md` →
> `.harness/inbox/inbox.md`, `PARKED.md` → `.harness/PARKED.md`, `events/` →
> `.harness/events/`, `state/` → `.harness/state/`. The engine scripts live in
> `.harness/runtime/` and the TUI in `.harness/presentation/textual/`. The six
> agents (`desk, groom, plan, build, review, distill`) are `.opencode/agent/*.md`;
> skills under `.harness/skills/` are registered via `opencode.json`.
> `.harness/loop.sh` and `.harness/dashboard.sh` are friendly wrappers.

---

## Part I — The change of posture

In the two previous versions, every point of ambiguity (uncertain priority,
architecture conflict, aesthetic verification) had an emergency exit: write `ask:`
in the INBOX or block in `BLOCKED.md` and wait for you. That is the dominant
pattern in the agent literature ("human-in-the-loop"), but it has a cost you do
not want to pay: every time the loop hits one of those walls, it stops producing
value until you open the chat again. In a system meant to run alone for hours
processing an intake backlog, that is the bottleneck — the loop moves only as fast
as your availability to answer questions, which is exactly what you wanted to
eliminate.

The correction is: **intake is input, never conversation.** You dump — no
structure, no need to "prepare" the item — and from there every decision (what is
this, what priority, is it viable, does it conflict with what exists, what is the
smallest slice that delivers value, is it done) is resolved inside the Main Loop,
by mechanism, not by question. The human's role shrinks to two things: feed the
INBOX when you want, and read what the system decided — never decide on its behalf
during execution.

This is not "the system never errs". It is "the system errs, documents why it
erred that way, and you correct it later — via a new intake item, not a pause
mid-cycle". The cost of erring becomes recorded rework, not stopped loop time.
That trade is only safe because promote-on-green (gates) still exists: the system
can decide wrong about *what* to build, but not about *whether the code is
correct* — the gates still hard-stop that for real.

---

## Part II — The nine principles

The eight from the previous version still hold. The ninth is the formalization of
all this:

**1 — Two loops, a single point of contact.** Half Loop and Main Loop speak only
through `INBOX.md`.

**2 — Memory lives on disk; context is ephemeral.**

**3 — The loop never lies.** It ends with a visible error instead of a false
"done" — but note: this is about honesty of *progress*, it is no longer an exit to
push a decision onto the human (see Principle 9).

**4 — The primary context is a scheduler.** It delegates heavy search to
subagents.

**5 — Backpressure and promote-on-green.** A failed gate rejects the iteration;
only validated state reaches `main`.

**6 — Telemetry for free.**

**7 — Perceptual verification is asynchronous, never blocking.** A reformulation of
the old "the human judges what the machine cannot measure". The
programmatic/perceptual distinction remains — but perceptual no longer pauses the
loop (see Part VI). The system produces the artefact, records it in a bulletin, and
**keeps working on the next item**. You judge when you want; the judgment becomes
feedback (silent approval by omission, or correction via a new intake item), never
a closed gate.

**8 — Every relevant event is published on the bus**, and the publication is the
contract — not the UI that reads it.

**9 — Post-intake decisions are always autonomous, always grounded, always
reversible when possible.** This is the central principle of this version. Every
time the system faces ambiguity — priority, viability, conflict, scope — it
resolves it with one of the Decision Engine mechanisms (Part V), never by writing a
question back to you. Every autonomous decision is: (a) grounded in real research
against the code and the living documents, never in empty guesswork; (b) recorded
with the reasoning and an explicit confidence level; (c) taken with a
reversibility bias — when two readings are plausible, the system prefers the one
cheaper to undo later.

---

## Part III — File map

```
project/                            (realized under .harness/ — see the note at top)
├── AGENTS.md                       # constitution: deterministic stack, subagent policy, ownership
├── README.md                       # bootstrap prompt
│
├── .opencode/agent/                # desk, groom, plan, build, review, distill
│
├── .harness/                       # THE ENGINE
│   ├── loop.sh                     #   Main Loop entrypoint
│   ├── dashboard.sh                #   TUI/HTML entrypoint (auto-detects)
│   └── runtime/
│       ├── scheduler.sh  cycle.sh  intake_loop.sh
│       ├── decide.sh               #   *** the Decision Engine dispatcher (Part V) ***
│       ├── scoring.sh              #   WSJF — autonomous priority
│       ├── precedence.sh           #   conflict-resolution hierarchy
│       ├── state.sh  events.sh  context.sh  memory.sh  git.sh  gates.sh  agents_run.sh
│   └── presentation/
│       ├── textual/                #   the TUI (app.py + widgets, incl. decision_log)
│       └── html/dashboard.sh       #   static HTML from bus + state
│
├── inbox/inbox.md                  # intake dump — no required structure
├── PARKED.md                       # tasks stopped by a MISSING EXTERNAL RESOURCE (not a decision)
│
├── tasks/TASK-{id}.md
├── state/{runtime,working_context}.json, understanding.json
├── events/{date}.jsonl
│
├── memory/
│   ├── intent.jsonl                # intent ledger — episodic
│   ├── decisions.md                # ADRs — semantic, with precedence
│   ├── assumptions.md              # *** assumptions made under uncertainty, with confidence ***
│   ├── learnings.md  patterns.md   # semantic
│   └── history/
│
├── specs/
│   ├── PRODUCT.md
│   ├── ARCHITECTURE.md             # includes the INVARIANTS — see Part V.3
│   ├── ROADMAP.md  SPRINT.md
│   └── DECISION_POLICY.md          # *** the weights and rules the Decision Engine uses ***
│
├── skills/{name}/SKILL.md   mcp/{name}/   logs/
```

Two new files carry the weight of the posture change: `memory/assumptions.md`
(every assumption made under uncertainty is recorded and traceable) and
`spec/DECISION_POLICY.md` (the weights and precedence rules you define **once**, at
bootstrap, so you never have to be consulted item by item). Writing that decision
policy is the only place your judgment enters the system structurally — after that,
the system applies the policy on its own.

---

## Part IV — The Intake Engine

Intake is the single point where you talk to the system, and the rule is: **you
never have to format anything.** It can be a loose sentence, a list, a half-formed
idea, a badly described bug, a three-paragraph product vision. `desk` (via the Half
Loop, a light daemon separate from the Main Loop) receives it and always does three
things:

1. **Classifies the type** — `feature`, `bug`, `adjustment` (change to something
   existing), `modeling` (data/domain), `vision` (a product/customer directive,
   more abstract than a feature). The classification is a content heuristic
   (keywords, whether it references something already in ARCHITECTURE.md vs
   something new), never a question "is this a bug or a feature?" — if ambiguous, it
   tags `type_confidence: low` and classifies by the most likely guess. Getting the
   class wrong is not serious: `groom` reclassifies later with more context, and
   reclassification is not a decision that needs you.

2. **Marks initial confidence and apparent scope**, without judging viability —
   viability is `plan`'s job, not `desk`'s. `desk` only records what you said, as
   faithfully as possible, with a type tag and a *suggested* priority (not decided —
   the final priority comes from the WSJF in `groom`, Part V.1).

3. **Writes to the INBOX and never waits for a reply.** Unlike the previous version,
   `desk` no longer has a "judgment mode" that depends on you answering to unblock
   something. It has only two modes now:

   - **Capture mode** — you speak, it distils and files. Always available, always
     immediate.
   - **Bulletin mode** — when you open a new conversation, it shows you (without
     asking anything) a summary of what the Main Loop decided on its own since last
     time: what was built, what was rejected and why, which assumptions were made at
     low confidence (candidates to correct if you want, but not required), and
     what is in `PARKED.md`. It is informative, not interactive — you can ignore it
     entirely and the system keeps going.

INBOX item contract (loose format; `desk` does the structuring):

```markdown
## [I-142] type: feature · type_confidence: high · origin: chat 2026-06-30T14:02
"I want to export a demo's stats to CSV, straight from the replay screen"
```

No priority field filled by you, no "awaiting approval" field. The item enters the
queue and `groom` decides the rest.

---

## Part V — The Decision Engine (the central piece)

This is the direct answer to what was missing. Every point that used to have an
`ask:` exit now consults one of these four mechanisms, in this order of
application. `decide.sh` is the script the agents call — it never writes prose, only
applies a rule and returns a structured verdict the agent folds into its own
reasoning.

### V.1 — Autonomous prioritization: WSJF (Weighted Shortest Job First)

A technique borrowed from SAFe (Scaled Agile), designed exactly for teams/systems
that must order a continuous backlog without renegotiating priority per item. The
formula:

```
WSJF = Cost of Delay / Job Duration
Cost of Delay = Business Value + Time Criticality + Risk Reduction
```

In the Harness, each component is estimated by `groom` against concrete signals, not
hunches:

- **Business value** — does the item reference a module already described as
  priority in `PRODUCT.md`? How many other ROADMAP items depend on it? (Out-degree
  in a simple dependency graph.)
- **Time criticality** — is it a `bug` breaking something already in production
  (high) vs a long-term `vision` (low)?
- **Risk reduction** — does the item unlock knowledge or infrastructure other items
  will need? (E.g. a data model three future features depend on.)
- **Job duration** — estimated by `plan` via gap analysis against the real code (the
  same technique as previous versions), not a hunch.

The result is a number. Higher WSJF first. This completely replaces asking "is this
more important than that?" — the formula answers, and the formula is documented in
`spec/DECISION_POLICY.md`, where you set the relative weights **once** (e.g.
"production bugs always weigh 3x a new feature"). After that, `groom` recomputes the
WSJF of the whole ROADMAP each cycle, because the backlog changes (a new item
enters, a dependency resolves).

### V.2 — Viability: gap analysis + vertical-slice decomposition, never a block

`plan` (same responsibility as before: read the real code via subagents, check
against `ARCHITECTURE.md`) changes what it does when it finds an item that *looks*
infeasible as requested. Previously it "backed off": marked it blocked and wrote
why, waiting for you. Now it has a sequence of attempts before considering anything
un-doable:

1. **Minimum vertical slice** (*vertical slice decomposition*, a classic agile
   technique): instead of asking "this is too big, do you still want it?", `plan`
   decomposes the item into the smallest slice that delivers observable value on its
   own, and queues only that slice as a task. The rest returns to the ROADMAP as
   child items, each re-scored by WSJF — naturally, what remains can rise or fall in
   priority on its own.
2. **Reinterpretation under the invariants** — if the request conflicts with an
   architecture invariant (see V.3), `plan` does not ask "want me to ignore it?". It
   applies the precedence hierarchy: the invariant always wins. It then tries to
   reformulate the request in a way that preserves the original intent without
   violating the invariant (e.g. "export CSV straight from the DB" conflicts with
   the invariant "all data reads go through the API layer"; the automatic
   reinterpretation is "export CSV via a new API endpoint", which preserves the
   intent and respects the invariant).
3. **Documented rejection** — only if the two attempts above fail (the item
   genuinely has no viable slice and no intent-preserving reinterpretation) does
   `plan` mark the item `status: auto-rejected` in the ROADMAP, write the full
   reasoning to `memory/decisions.md`, and — importantly — **stop nothing**. The
   cycle moves to the next item. You find out in the next `desk` bulletin, and if
   you disagree, you reopen it as a new intake item with the rejection context
   already attached.

### V.3 — Conflict: precedence hierarchy

When two sources of truth appear to contradict (a new request conflicts with an old
decision, two ROADMAP items ask for incompatible things), the system applies a
fixed order, defined once in `AGENTS.md` and consulted by `precedence.sh`:

```
1. ARCHITECTURE.md invariants          (security, data integrity — never yields)
2. Most recent decision in decisions.md (an explicit supersede always beats the old)
3. ROADMAP item with the higher WSJF    (calculated priority beats implicit priority)
4. Reversibility heuristic (V.4)        (in doubt, the option cheaper to undo)
5. Smallest change surface              (the smaller diff, when options are equal in risk)
```

This chain is why the system never needs to ask "what if this contradicts that?" —
the answer is always mechanical: climb the chain until the first criterion breaks
the tie.

**Invariants** deserve emphasis: they are a small set of non-negotiable rules you
write once in `ARCHITECTURE.md` (e.g. "never DELETE without soft-delete", "every
write of sensitive data passes through an audit", "no new feature breaks backward
compatibility of the public API"). Invariants are the only thing in the system with
absolute veto power — and precisely because of that, defining invariants well is the
most important architecture work you do at bootstrap, because it is what guarantees
that full autonomy does not become the freedom to do something irreversibly stupid.

### V.4 — Decisions under uncertainty: one-way vs two-way doors

A named technique — from how Amazon formalized autonomous decision-making at scale
(Jeff Bezos, 1997 shareholder letter): decisions are of two kinds.

- **Two-way door** — reversible at low cost. Erring here is cheap: undo, try again.
  For these, the system decides fast, at default `medium` confidence, applies the
  most reasonable default (usually: the additive, non-destructive option, behind a
  feature flag when it fits) and moves on. It is not worth spending a "deep
  research" cycle on a two-way door — the cost of researching exceeds the cost of
  erring and correcting later.

- **One-way door** — irreversible or costly to undo (destructive schema migration,
  data removal, public API contract change). For these, the system **does not ask
  you** — but it raises the evidence bar before acting: it dispatches a deeper
  research subagent against the code and the living documents, requires `high`
  confidence before proceeding, and if confidence still stays `low`, prefers the
  minimum vertical slice that does **not** close the door (e.g. instead of dropping
  a DB column now, it marks it deprecated and defers the physical removal to a
  future low-risk item). The rule is not "ask the human when it is risky" — it is
  "spend more reasoning and prefer reversibility when it is risky".

Every decision, of both kinds, is recorded in `memory/decisions.md` with the door
type, the confidence level, and the reasoning. This is what makes the system
auditable without making it dependent on approval.

### V.5 — Assumptions under ambiguity: the assumption-logging protocol

When the intake item is genuinely ambiguous (two plausible readings, neither
clearly right) and there is no invariant or prior decision to break the tie, the
system **does not pause for clarification**. It picks the reading most aligned with
`PRODUCT.md` and the pattern already established in code (consistency > novelty, in
doubt), and records it in `memory/assumptions.md`:

```markdown
## A-031 · TASK-142 · confidence: low · door: two-way
Assumption: "export stats" means CSV, not Excel, because the project's other
exports already use CSV as the default.
If wrong: trivial to add Excel later, it is additive.
```

`memory/assumptions.md` is the file you open when you want to audit specifically
where the system had to "guess" with grounding. It is different from `decisions.md`
(which records decisions made with sufficient confidence) — assumptions are the
low-confidence subset, deliberately isolated so you can review just that slice
without digging through everything.

---

## Part VI — What no longer blocks: the conversion table

| Situation that used to produce `ask:`/`BLOCKED` | Autonomous resolution now | Mechanism |
|---|---|---|
| Priority between two items uncertain | Calculated, not asked | WSJF (V.1) |
| Item seems too big/infeasible | Decompose into the minimum slice | Vertical slice (V.2) |
| Conflicts with existing architecture | Reinterpret preserving intent; if impossible, reject and document | Precedence + invariants (V.2, V.3) |
| Two documents seem to contradict | Climb the precedence chain until it breaks the tie | `precedence.sh` (V.3) |
| Ambiguous, no criterion to break the tie | Pick the most consistent reading, log the assumption | Assumption log (V.5) |
| Risky/irreversible change | Raise the evidence bar, prefer the reversible slice | One-way vs two-way door (V.4) |
| Aesthetic/perceptual verification | Produce the artefact, record it in the bulletin, move to the next item | Async judgment queue (Principle 7) |
| Missing credential/external resource (API key, paid account) | **Only that task** goes to `PARKED.md`; the loop continues with the rest of the backlog | Parked-task isolation (below) |

The only row that still "stops" anything is the last — and note that it stops *the
task*, never *the loop*. It is a different category from everything else: it is not
a decision the system could make on its own (it physically does not have the API
key), it is a real external dependency. `PARKED.md` exists only for that, and the
rule is strict: a parked item is never a reason for `loop.sh`'s phase decision to
consider the cycle `done` — it is ignored in the phase decision (as if it did not
exist) until the resource appears, and `groom` re-checks parked items every cycle in
case the context changed (e.g. you mentioned the key in an intake chat without
realizing it unblocked something).

This resolves the central concern: nothing in the intake→decision→execution flow
waits for your reply. The only thing that waits is a physical dependency that does
not exist yet, and even that does not stall the rest of the system.

---

## Part VII — Agents

| Agent | Loop | Touches code? | Decides on its own | Writes |
|---|---|---|---|---|
| `desk` | half | no | type classification, bulletin | `inbox.md` |
| `groom` | main | no | WSJF, incorporation into ROADMAP | `ROADMAP.md`, `memory/intent.jsonl` |
| `plan` | main | reads | viability, decomposition, reinterpretation, rejection | `SPRINT.md`, `tasks/*.md`, `memory/decisions.md`, `memory/assumptions.md` |
| `build` | main | edits | implementation within the task contract | code |
| `review` | main | diff only | done/retry, semantic consolidation, gate judgment | `memory/decisions.md`, `learnings.md`, `patterns.md`, `understanding.json` |
| `distill` | main | no | becomes a skill or an MCP | `skills/*`, `mcp/*` (quarantine) |

Boundary kept: only `plan` and `build` touch code. Change from previous versions:
**no agent may write a decision request back to `INBOX.md` or create an item in a
blocked file for anything other than "a physical external resource is missing"**.
This restriction is enforced by the contract layer — each agent's frontmatter
declares `writes:`, and `PARKED.md` is only a permitted destination when the
structured reason is `missing_external_resource`. Any attempt to write there for
another reason is rejected and becomes an incident in `decisions.md` — the system
self-audits against its own temptation to ask for easy help.

---

## Part VIII — The engine (`loop.sh`)

Same backbone as before — doctor, decide phase, fingerprint before, session
isolation, fingerprint after, failure evaluation, commit+event, promote-on-green,
maintenance — with one adjustment to the phase decision:

```
decide_phase():
  if INBOX has a new item                     -> groom
  else if SPRINT has an escalated ([!]) task   -> plan   (re-decide it)
  else if SPRINT has an open ([ ]) task         -> build
  else if ROADMAP has a pending item           -> plan
  else                                         -> done
  # SPRINT tasks in [p] (parked) or [!] (escalated) are invisible to open/done,
  # so a stuck task never blocks the ones behind it.
```

(Review and distill run inline after a build.) Crucially, a **repeated failure or
sterility is a decision point, not a reason to halt** — killing the runtime and
waiting for a human to notice a red dashboard would be a disguised block, which
Principle 9 forbids. So the breakers **escalate instead of dying**: a build that
fails/stalls repeatedly has its task marked `[!]` and routed back to `plan` to
re-decide (smaller slice / reinterpret / auto-reject); a `plan` that cannot
decompose an item auto-rejects it; a `groom` looping on a malformed dump drops it.
The failed attempt is rolled back, the escalation committed, the breaker reset, and
the loop lives on. `die()` (honest termination) is reserved for genuine
**infrastructure** failure that no decision can resolve — missing `git`, `opencode`,
or `PRODUCT.md`, or the absolute iteration ceiling. A healthy system with an empty
backlog ends in `done` for real; a system with a parked
item keeps running the rest of the backlog.

---

## Part IX — Event bus

New domains relative to the previous version:

| Domain | New events |
|---|---|
| decision | `decision.made`, `decision.assumption_logged`, `decision.auto_rejected`, `decision.reinterpreted`, `decision.escalated` |
| task | `task.parked`, `task.unparked`, `task.decomposed` |

`decide.sh` publishes `decision.*` every time any Part V mechanism fires — this is
what feeds the TUI's Decision Log (Part XII), the transparency piece that
compensates for the system never asking anything: you do not approve decisions in
real time, but you can see the complete trail of each one, with reasoning, at any
moment.

---

## Part X — Memory

No structural change from the previous fusion (CoALA as the model, curated docs as
the implementation), with `memory/assumptions.md` added as a fifth drawer inside
semantic — specifically the low-confidence decisions, isolated for quick audit
(Part V.5).

| CoALA layer | File | Who writes | Life |
|---|---|---|---|
| Working | `state/working_context.json` | `context.sh` | 1 cycle |
| Episodic | `memory/intent.jsonl`, `events/*.jsonl`, `memory/history/*` | agents / `events.sh` / `archive.sh` | permanent, append-only |
| Semantic | `decisions.md`, `assumptions.md`, `learnings.md`, `patterns.md` | `plan`/`review` | permanent, editable, configurable retention |
| Procedural | `AGENTS.md`, `skills/*`, `mcp/*` | human + `distill` | permanent, versioned |

---

## Part XI — Distillation Engine and Gates

No change from the previous fusion — "N+ tool calls or a repeated pattern becomes a
skill/MCP" and the cheap→expensive gate battery stay exactly as specified, because
neither depended on the blocking pattern that was removed.

---

## Part XII — Presentation Layer: `dashboard.sh` and the real TUI

### XII.1 — `dashboard.sh`, the single entrypoint

Called without arguments in a real terminal, it opens the TUI. Called from
cron/CI/SSH without a tty, it falls back to `html` on its own — the mode `loop.sh`
uses in its maintenance step, best-effort, never blocking the cycle. (In this repo,
the TUI is `.harness/presentation/textual/app.py` and the HTML generator is
`.harness/presentation/html/dashboard.sh`.)

### XII.2 — TUI architecture (Textual)

```
.harness/presentation/textual/
├── app.py                  # HarnessApp(App) — mounts the screens, global keybindings
├── reader.py               # read-only state/events/decisions access
└── widgets/
    ├── cycle_status.py     # phase, health, cycle N, loop PID
    ├── agents_panel.py     # who ran last, when, result
    ├── current_task.py     # active TASK, progress
    ├── event_log.py        # tail of events/*.jsonl, scrollable
    ├── decision_log.py     # *** the new screen: why the loop decided each thing ***
    └── parked_panel.py     # items in PARKED.md, reason, how long
```

Single data source for everything: `state/runtime.json` (polled every ~500 ms) +
`events/*.jsonl` (incremental tail, never a full re-read). The TUI never reads
`spec/` or `memory/` directly to build the main panel — only to open a specific
decision's detail when you navigate to it (lazy load, on demand).

Rendered layout (main screen, before navigating to the Decision Log):

```
┌──────────────────────────────────────────────────────────────────────┐
│ Harness · cycle 184 · health 🟢 · PID 4021                            │
├───────────────────────────┬──────────────────────────────────────────┤
│ Agents                    │ Events                                 ▲  │
│ ● build    running        │ 14:02:01 build.started TASK-088         │
│ ○ review   idle           │ 14:02:19 decision.reinterpreted I-142   │
│ ○ groom    idle           │ 14:02:41 build.finished TASK-088       ▼ │
├───────────────────────────┤                                          │
│ Current Task              │                                          │
│ TASK-088 · 62%            │                                          │
├───────────────────────────┤                                          │
│ Parked: 1 (STEAM_API_KEY) │                                          │
└───────────────────────────┴──────────────────────────────────────────┘
[q] quit  [d] decision log  [x] stop  [r] run  [g] gen dashboard
```

On mount, if the runtime is not running, the TUI starts `loop.sh --daemon`
detached (closing the TUI does not kill the runtime — the launch is the TUI's only
write action).

### XII.3 — The screen that compensates for full autonomy: Decision Log

Because the system never asks, the only way to trust it is to be able to audit
quickly *why* it decided each thing. `decision_log.py` is a navigable list, newest
first, pulling from `events/*.jsonl` (index) and `memory/decisions.md` +
`memory/assumptions.md` (content, loaded on demand):

```
┌─ Decision Log ─────────────────────────────────────────────────────────┐
│ 14:02:19  I-142  reinterpreted   conf: high  door: two-way              │
│ 13:58:02  I-140  auto_rejected   conf: high  door: one-way              │
│ 13:41:10  I-139  assumption      conf: low   door: two-way              │
│                                                                          │
│ > I-142 · "export demo stats to CSV"                                    │
│   Original request conflicted with the invariant "data reads only via    │
│   the API" (ARCHITECTURE.md). Reinterpreted as: new endpoint             │
│   GET /demos/{id}/export, same intent, no invariant violation.           │
│   Slice: TASK-088 (endpoint) + TASK-089 (UI button, queued).             │
└──────────────────────────────────────────────────────────────────────┘
```

This screen is, in practice, the functional substitute for the old approval flow —
only asynchronous and without blocking power. You audit when you want, disagree when
you want, and disagreeing becomes a normal intake item, not a reply to a pending
question.

### XII.4 — HTML and Slack, same source

The HTML generator and an optional Slack notifier (subscribing to `decision.*`,
`task.parked`, `runtime.health.*`, `distill.*`) read exactly the same bus as the
TUI, so the consumers never diverge. Notifying `decision.auto_rejected` and
`task.parked` is the closest the system gets to "letting you know" — but it is a
notification, not a question. No reply expected, no loop stopped waiting for a
reaction.

---

## Part XIII — Ownership / Contracts

| File | Owner | Editable by | Layer |
|---|---|---|---|
| `PRODUCT.md` | human | human + `groom` | spec |
| `ARCHITECTURE.md` (with invariants) | human + `plan` | human + `plan` + `review` | spec |
| `DECISION_POLICY.md` | human | human (rare, weight review) | spec |
| `ROADMAP.md` | `groom` | yes | spec |
| `SPRINT.md` | `plan` | regenerable | spec |
| `inbox.md` | `desk` | `desk` (append), `groom` (consumes) | signal |
| `PARKED.md` | `plan`/`build` | only reason `missing_external_resource` | signal, restricted |
| `memory/decisions.md` | `plan`/`review` | append/supersede | semantic |
| `memory/assumptions.md` | `plan` | append | semantic |
| `state/*.json` | scripts | **script only** | working/runtime |
| `events/*.jsonl` | `events.sh` | **script only** | episodic (bus) |
| `skills/*`, `mcp/*` | `distill` | proposed, human-approved merge when you want to review | procedural |
| `dashboard/index.html` | `dashboard.sh` | no (generated) | presentation |

A `writes:` violation (an agent trying to write `PARKED.md`/`inbox.md` outside the
permitted reason, for example) aborts the cycle and becomes an incident — the
technical lock that ensures Principle 9 is not just a promise in markdown.

---

## Part XIV — Implementation roadmap

**0 — Skeleton.** Full tree, `AGENTS.md` with the deterministic stack, ownership,
and each agent's `writes:` declaration already restricting `PARKED.md`.

**1 — Engine + bus from day one.** `loop.sh`, `state.sh`, `events.sh` publishing the
commit+event pair. Retrofitting later is rework.

**2 — Decision Engine.** `decide.sh`, `scoring.sh` (WSJF), `precedence.sh`, and
`spec/DECISION_POLICY.md` written by you at bootstrap — the WSJF weights and the
architecture invariants are the system's only structural manual input. Spend real
time here.

**3 — Memory.** `intent.jsonl`, `decisions.md`, `assumptions.md`, `archive.sh`,
promote-on-green.

**4 — Ralph agents** with the new discipline of never writing a decision request
back — specifically testing that `plan` decomposes/reinterprets/rejects instead of
blocking is the most important acceptance test of this stage.

**5 — Half Loop.** `inbox.md` with no required structure, `desk` with only capture
mode + bulletin mode (no blocking judgment mode).

**6 — `dashboard.sh` html mode.** Validate the data source (bus + state) before
complicating with the TUI.

**7 — Gates.**

**8 — Full TUI**, including the Decision Log — the piece that gives you the
confidence to let the system run unsupervised, so do not skip it.

**9 — Slack notifier + Distillation Engine.**

**10 — Specialization** for the concrete project: skill catalogue, domain gates,
specific invariants, seed `ARCHITECTURE.md`.

---

## Appendix — Glossary of named techniques

**WSJF (Weighted Shortest Job First)** — backlog prioritization by cost-of-delay
over duration, from SAFe; removes the need to renegotiate priority per item.
**Vertical slice decomposition** — break a big request into the smallest slice that
delivers observable value on its own. **Precedence hierarchy** — an ordered chain of
tie-breakers (invariant > recent decision > WSJF > reversibility > smallest diff),
applied mechanically against any conflict. **Architecture invariants** — absolute
veto rules, defined once, never negotiable by an agent. **One-way vs two-way door
decisions** — Bezos's (1997) framework to calibrate how much reasoning/evidence a
decision needs, based on how costly it is to reverse. **Assumption logging** —
explicit, isolated recording of every assumption made under genuine ambiguity, with
confidence and a reversibility note. **Async judgment queue** — perceptual
verification becomes a recorded artefact, never a blocking gate. **Parked-task
isolation** — an item missing an external resource stalls only itself, never the
loop's phase decision. Plus the inherited terms: *filesystem-as-memory, fresh
context per iteration, content-fingerprint sterile detection, layered circuit
breakers, completion signal, honest termination, promote-on-green, liveness via PID
probe, deterministic stack, why-into-disk, progressive disclosure, MCP synthesis,
CoALA memory layers, distillation triggering.*
