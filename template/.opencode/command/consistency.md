---
description: Audit the living documents for contradictions (read-only)
---

Audit the Harness living documents for internal contradictions. This is a
read-only check — do not modify any file; only report findings.

Documents:
@.harness/specs/ARCHITECTURE.md
@.harness/specs/ROADMAP.md
@.harness/specs/SPRINT.md
@.harness/memory/decisions.md

Check specifically:
1. `ARCHITECTURE.md` must not contradict any record in `decisions.md` (a later
   decision supersedes an earlier one — flag only against the most recent
   applicable decision).
2. `SPRINT.md` tasks must trace to a `## [planned]` item in `ROADMAP.md`; flag
   orphan tasks that belong to no roadmap item.
3. Roadmap items marked `## [done]` should have no remaining open sprint tasks.
4. Every roadmap and inbox heading should carry a known state
   (`pending | planned | done | blocked`).

Report each finding as: the file(s) involved, the specific contradiction, and a
one-line suggested resolution. If everything is consistent, say so plainly.
