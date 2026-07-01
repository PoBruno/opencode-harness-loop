---
description: Audit the Harness specs, seeds, and agent prompts for under-specification — unfilled placeholders, prose-only guarantees with no enforcement, v3 vocabulary drift, and orphaned promises between agents (read-only)
---

Audit the Harness deliverables for **lack of depth**, not just contradiction —
`consistency.md` already checks whether documents agree with each other; this
checks whether they are actually *finished* and whether a guarantee stated in one
place is *implemented* somewhere else, not just repeated in prose. Read-only — do
not modify any file, only report findings.

Documents and code to read:
@AGENTS.md
@.harness/specs/PRODUCT.md
@.harness/specs/ARCHITECTURE.md
@.harness/specs/DECISION_POLICY.md
@.harness/specs/ROADMAP.md
@.opencode/agent/desk.md
@.opencode/agent/groom.md
@.opencode/agent/plan.md
@.opencode/agent/build.md
@.opencode/agent/review.md
@.opencode/agent/distill.md
@.opencode/command/consistency.md
!`grep -rn "reason:\|missing_external_resource" .harness/runtime/state.sh .harness/runtime/*.sh 2>/dev/null || echo "(no reason: validation found in runtime scripts)"`

## 1. Unfilled placeholders

Search every spec and seed for literal `{{...}}` tokens or a WSJF weights block
where `business_value`, `time_criticality`, and `risk_reduction` are all still the
default `1`. Flag each one — especially `ARCHITECTURE.md`'s INVARIANTS section,
since an empty invariant set means the autonomous loop currently has **zero**
absolute veto. Distinguish "template not yet run through bootstrap" (expected,
low severity) from "bootstrap ran and this is still empty" (high severity —
check `git log` for a bootstrap commit as the signal).

## 2. Vocabulary drift (v3 -> v4)

The v4 doctrine deleted the human-blocking pattern. Grep every spec, seed, and
agent file for leftover v3 terms that should not exist post-migration:
`blocked` (as a state token, not inside `PARKED.md`'s
`missing_external_resource` context), `ask:`, `awaiting approval`,
`[blocked]`. For each hit, quote the file, the line, and say whether it is a
harmless historical reference (e.g. inside a comment explaining what was
removed, or a prohibition) or an active vocabulary leak (e.g. a state enum, a
check, a template placeholder). **Specifically cross-check**: extract the literal
state enum defined in `ROADMAP.md`'s template comment, then check whether
`consistency.md`, `status.md`, or any dashboard/reader code references a state
token *not* in that enum, or fails to reference one that *is* in it. A mismatch
here is a real bug, not a style nit.

## 3. Prose-only guarantees (asserted but not enforced)

For every sentence across the agent files that claims something is rejected,
validated, or restricted by "the runtime" or "the contract" (e.g. "`PARKED.md`
is only for `missing_external_resource` — the runtime rejects any other
reason"), search the actual runtime scripts (`state.sh` and the rest of
`runtime/`) for a matching validation. Report each guarantee as one of:
- **enforced** — found the matching check, cite the line.
- **prose-only** — the guarantee is repeated across N agent prompts but no
  script actually validates it. This is the highest-severity finding category:
  it means the doctrine currently depends on the agent choosing to obey its own
  instructions, not on a technical block.

## 4. Orphaned promises between agents

Cross-reference what one agent claims to *produce* against what any agent
claims to *consume*. Specifically check:
- Does `review.md` write anything (e.g. a "pending async judgment" note) that
  no other agent's read list or protocol ever surfaces to the human? `desk.md`'s
  bulletin mode is the natural consumer — confirm its bullet categories actually
  cover every kind of note `review.md` can write.
- Does `distill.md` put anything into a state (e.g. MCP quarantine) that no
  agent's protocol ever transitions out of? If no file documents the promotion
  path from quarantine to approved, flag it explicitly — a write-only state is
  a dead end.
- Does any agent's example or template contain a non-English token (a quick
  heuristic: words like `alta`, `nao`, `entao`, `origem`, `tipo`) in a file that
  is supposed to be fully English?

## Report format

One table, one row per finding:

| # | File(s) | Finding | Severity | Suggested fix |
|---|---|---|---|---|

Severity: **critical** (invariants empty, or a v3 blocking path still reachable),
**high** (prose-only enforcement, orphaned promise a human depends on),
**medium** (vocabulary drift, unfilled non-safety-critical field), **low**
(cosmetic, leftover comment). If a category has no findings, say so plainly —
do not pad the report.
