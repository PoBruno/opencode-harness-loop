# Evaluating a skill's triggers

A skill earns its place only if it fires at the right time and stays quiet
otherwise. Treat the `description` as a classifier and test it like one.

## The rubric

For each candidate `description`, score it against two prompt sets:

- **SHOULD-fire set** (3–4 prompts): realistic ways a user phrases the task.
  Every one must clearly map to this skill.
- **SHOULD-NOT-fire set** (2+ prompts): adjacent tasks that a sloppy
  description would wrongly capture.

Pass condition: all SHOULD prompts map to the skill, and no SHOULD-NOT prompt
does. A single false positive is a failure — tighten before shipping.

## Tightening techniques

- **Front-load keywords.** Put the literal nouns, verbs, and filenames the user
  will say at the very start of the description.
- **Add a gate.** Prefix the scope with `Use ONLY when …` and name the adjacent
  topics it must ignore.
- **Name the artefacts.** If the skill is about specific files (`opencode.json`,
  `Dockerfile`), say so — concrete anchors beat abstract summaries.

## Example

Weak:    `description: Helps with deployment.`
Strong:  `description: Use ONLY when deploying THIS project to a cloud provider
         (AWS, GCP, Azure) — building the image, pushing, and applying infra.
         Not for local docker-compose or CI config.`

The strong version fires on "deploy to AWS" and stays silent on "run it locally
with docker-compose".
