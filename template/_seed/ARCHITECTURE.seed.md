<!--
  ARCHITECTURE.seed.md — the seed for .harness/specs/ARCHITECTURE.md.

  ARCHITECTURE.md describes the system in the BUILDER's terms: services, the
  contracts between them, structural decisions, and the quality gates. It is the
  technical contract every Main-Loop agent respects.

  - Existing project: the installer populates this from the real code (read via
    the `explore` subagent); describe what exists, do not invent.
  - New project: leave the prompts for `/bootstrap`.

  NOTE: this is the seed for the TARGET project's architecture. It is unrelated
  to docs/ARCHITECTURE.md in the template repo, which documents the Harness
  runtime itself. Delete this comment block once populated.
-->

# Architecture

## Stack

{{Languages, frameworks, runtimes, and package managers with versions.}}

## Services / components

- {{component}} — {{responsibility}}

## Contracts

{{The interfaces between components: APIs, schemas, events, shared types — the
contracts that must not break silently.}}

## Structural decisions

{{Key decisions that shape the system (and a one-line why). These graduate into
.harness/memory/decisions.md as the project evolves.}}

## Invariants (absolute veto)

A small set of non-negotiable rules. They are the ONLY thing with absolute veto
power in the autonomous system — the Decision Engine reinterprets requests to
preserve intent WITHOUT violating an invariant, and never overrides one. Writing
these well at bootstrap is the most important architecture work you do, because it
is what keeps full autonomy from doing something irreversible. Examples (replace
with your project's):

- {{never DELETE without soft-delete}}
- {{every write of sensitive data passes through an audit log}}
- {{no new feature breaks backward compatibility of the public API}}
- {{all data reads go through the API layer}}

## Quality gates

The Review Engine runs these cheap → expensive; any failure rejects the cycle.
Fill `.harness/gates.local.sh` with the real commands (exporting GATE_TYPECHECK,
GATE_LINT, GATE_TEST, GATE_BUILD) or rely on auto-detection.

- type-check: `{{...}}`
- lint:       `{{...}}`
- test:       `{{...}}`
- build:      `{{...}}`

## Boundaries

{{Directories that are generated and must never be hand-edited; external systems
the agent must not touch.}}
