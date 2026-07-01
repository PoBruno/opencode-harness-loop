<!--
  AGENTS.seed.md — the skeleton the installer fills to produce AGENTS.md (at the
  project root). The installer replaces every {{PLACEHOLDER}} with facts from
  reconnaissance and KEEPS the "[Harness]" sections as-is. A generic or
  auto-duplicated AGENTS.md HURTS agent performance — keep it minimal and
  high-signal: only what the agent cannot infer from the code. Delete this
  comment block in the generated file.
-->

# AGENTS.md

## Project

{{ONE OR TWO LINES: what this project is, language and framework with versions.}}

## Commands

Copy-pasteable, with the real flags detected during install:

- Build:       `{{BUILD_COMMAND}}`
- Test (all):  `{{TEST_COMMAND}}`
- Test (one):  `{{SINGLE_TEST_COMMAND}}`
- Lint:        `{{LINT_COMMAND}}`
- Type-check:  `{{TYPECHECK_COMMAND}}`

## [Harness] Working context

Each cycle the Context Engine assembles `.harness/state/working_context.json`
(the task, the relevant architecture slice, recent decisions, understanding).
Read it first, then only the specific files your role names. Your primary
context is a SCHEDULER: dispatch the `explore` subagent to read large files and
return the slice — do not read the whole repo. Keep under ~100k tokens.

> Search and write may fan out across many subagents in parallel.
> **Validation always uses a single subagent, in series** — the correctness
> signal must arrive through one funnel.

## [Harness] Completion markers

- `build` ends with one of `RALPH_DONE` / `RALPH_BLOCKED` / `RALPH_ALL_DONE`.
- Every other autonomous loop ends with `RESULT: pass` or `RESULT: fail`.

## [Harness] Contracts (who writes what)

The runtime enforces these and rolls back any out-of-scope write:

- `desk`    → `.harness/inbox/inbox.md`
- `groom`   → `.harness/specs/ROADMAP.md`, `.harness/memory/intent.jsonl`, `.harness/inbox/`, `.harness/PARKED.md`
- `plan`    → `.harness/specs/SPRINT.md`, `ROADMAP.md`, `.harness/tasks/`, `.harness/memory/decisions.md`, `assumptions.md`, `.harness/PARKED.md`
- `build`   → project code only (plus `.harness/PARKED.md` for a missing resource)
- `review`  → `.harness/memory/`, `.harness/state/understanding.json`
- `distill` → `.harness/skills/`, `.harness/mcp/`

Never write `.harness/state/runtime.json` or `.harness/events/` — only the
runtime writes those.

## [Harness] Decision doctrine (never ask the human)

Intake is input, never conversation. After an item enters the INBOX, EVERY
decision is made autonomously — never written back as a question. Use the Decision
Engine (`.harness/runtime/decide.sh`):

- **Priority** → WSJF (`decide.sh wsjf ...`), weights in `spec/DECISION_POLICY.md`.
- **Viability** → vertical-slice decomposition; reinterpret under invariants; only
  then auto-reject (documented). Never block.
- **Conflict** → precedence chain: `invariant > recent decision > WSJF >
  reversibility > smallest diff` (`decide.sh precedence a b`).
- **Risk** → one-way vs two-way door (`decide.sh door "<change>"`): one-way demands
  high confidence and prefers the reversible slice.
- **Ambiguity** → pick the reading most consistent with PRODUCT.md and log it in
  `memory/assumptions.md`. Never pause for clarification.

**Invariants** in `ARCHITECTURE.md` are the only absolute veto. The ONLY thing that
ever waits on the human is a genuinely missing external resource (an API key) →
that one task goes to `.harness/PARKED.md` with `reason: missing_external_resource`;
the loop keeps running the rest. Writing a `[blocked]`/`ask:` request for any other
reason is a contract violation.

## [Harness] Git safety

- The runtime owns commit and rollback (one task = one commit). `build` never
  commits — it edits code and the runtime commits the validated cycle.
- NEVER force-push. NEVER commit `.harness/state/`, `.harness/events/`,
  `.harness/logs/`, or secrets.

## [Harness] Always / Never

There is no "ask first" category — the doctrine removes it. When you would want to
ask, you decide (via the Decision Engine) and document instead.

**Always:** read `working_context.json` first; write only within your scope; use
the Decision Engine for ambiguity; write the *why* into disk (build); consolidate
memory (review).

**Never ask the human a decision.** The only human-facing signal is a genuinely
missing external resource → `.harness/PARKED.md` (`reason:
missing_external_resource`), which parks one task, never the loop.

**Never:** force-push; write another agent's files; invent a task outside the
sprint (build); write a `[blocked]`/`ask:` request for a decision; grant an MCP
network access without Review approval.

## Conventions and boundaries

{{Generated/ignored directories that must never be hand-edited (dist/,
node_modules/, .next/, target/); any project-specific conventions.}}
