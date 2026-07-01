---
name: skill-creator
description: Use when creating, authoring, or optimizing an opencode skill (a SKILL.md procedure) — including when a phase keeps re-deriving the same how-to and you want to capture it. Guides an evaluation-driven workflow: interview, draft, generate trigger tests, install only the validated version.
---

# skill-creator — author skills that actually fire

A skill is a **procedure** (an SOP) the agent loads on demand. It describes
*how to do a thing*, not *who to be* (that is an agent). The single most
important field is the `description`: the agent sees only the name and
description before deciding whether to load the body, so the description is the
trigger and must be self-sufficient.

## Workflow

1. **Intent interview (short).** Ask: what task does this skill cover? What are
   the concrete trigger phrases/filenames a user would say? What must the agent
   never get wrong here? Capture three or four real example prompts that SHOULD
   fire it and two that should NOT.

2. **Draft the `SKILL.md`.** Folder `.harness/skills/<name>/SKILL.md`. Keep the
   body lean and procedural. Frontmatter:
   ```
   ---
   name: <lowercase-hyphenated, matches folder>
   description: <what it does AND when to use it; front-load trigger keywords;
                gate with "Use ONLY when..." if it should stay quiet on adjacent topics>
   ---
   ```
   Write the description in the third person ("Use when…", not "I help with…").

3. **Apply progressive disclosure.** Keep `SKILL.md` short. Push heavy detail
   into a `references/` folder, one file per subtopic, loaded only when needed.
   A cloud-deploy skill has a short `SKILL.md` that picks the provider plus
   `references/aws.md`, `references/gcp.md`, `references/azure.md` — the agent
   loads only the relevant one. Idle skills then cost almost nothing.

4. **Generate trigger tests.** Write the example prompts to
   `references/evals.md` and confirm the description fires on the SHOULD set and
   stays silent on the SHOULD-NOT set. If a SHOULD-NOT prompt would trigger it,
   tighten the description with a "Use ONLY when…" gate. See
   `references/evaluation.md` for the rubric.

5. **Install only the validated version.** Do not ship a skill whose triggers
   are fuzzy — a skill that fires at the wrong time is worse than no skill.

## Rules of thumb

- One skill = one coherent procedure. If the body needs "and" to span unrelated
  tasks, split it.
- Name the folder and the `name:` field identically.
- After adding a skill, remind the human to restart opencode (config is loaded
  at startup, not hot-reloaded).
