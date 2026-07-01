# Decision Policy

<!--
  The ONE place your judgment enters the system structurally. Written once at
  bootstrap; after that the Decision Engine applies it on its own, so priority is
  never renegotiated item by item. Edit rarely.

  scoring.sh reads the `key: number` weight lines under "WSJF weights". Keep those
  lines exactly one per key; the rubric below uses tables (rows start with `|`) so
  it is never mistaken for a weight.
-->

## WSJF weights

WSJF = Cost of Delay / job_duration, where
Cost of Delay = business_value*w_bv + time_criticality*w_tc + risk_reduction*w_rr.

These are opinionated **defaults** — tune them for the project at bootstrap. This
default says: urgency matters most, value and risk-reduction matter equally and
somewhat less.

business_value: 2
time_criticality: 3
risk_reduction: 2

## Rubric — how groom scores each component

Estimate every component on the **Fibonacci set {1, 2, 3, 5, 8, 13}** — never a
number outside it. Fibonacci forces meaningful gaps and stops the score from being
false-precise noise. Duration uses the same set (rough size, refined by `planner`'s
gap analysis).

| Score | business_value | time_criticality | risk_reduction | job_duration |
|---|---|---|---|---|
| 1  | cosmetic / nice-to-have | no deadline pressure | unlocks nothing else | a few edits, one file |
| 2  | minor UX polish | mild, can wait weeks | marginal | small, one module |
| 3  | a real user asked for it | this sprint-ish | de-risks one future item | a handful of files |
| 5  | touches a PRODUCT.md priority module | users are actively blocked | unlocks 2–3 future items | multi-module, some unknowns |
| 8  | core to the product's value | degrading prod experience now | unlocks a whole area (e.g. a data model) | large, cross-cutting |
| 13 | flagship / revenue-critical | production is broken NOW | foundational; most of the backlog waits on it | very large, many unknowns |

## Priority rules (concrete defaults — edit for the project)

- A `bug` that breaks something already in production scores `time_criticality: 13`
  (that is the "production bugs jump the queue" rule, applied through the rubric,
  not a magic multiplier).
- A `vision` item starts low on `time_criticality` (1–2): it is long-term.
- Data/domain `modeling` that several features depend on scores high on
  `risk_reduction` (8–13): it unblocks others.
- An `adjustment` to an existing, working feature rarely exceeds `business_value: 3`
  unless it is on a PRODUCT.md priority module.
- When two items tie on WSJF, the precedence chain in AGENTS.md breaks it (smaller
  diff / more reversible wins).

## Door defaults (V.4)

- two-way (reversible): decide fast, additive default, feature-flag when it fits.
- one-way (destructive migration, data removal, public-API break): require HIGH
  confidence; prefer the reversible slice (deprecate before deleting).

## Ambiguity default (V.5)

When two readings are plausible and nothing breaks the tie: prefer the one most
consistent with PRODUCT.md and existing code (consistency > novelty), and log the
assumption in `memory/assumptions.md`.
