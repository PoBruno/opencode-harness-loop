<!--
  PRODUCT.seed.md — the seed for .harness/specs/PRODUCT.md.

  PRODUCT.md describes the product in the USER's terms. It is the most stable
  document and the only project context `intake` and `desk` ever see, so it must
  be self-contained. The runtime refuses to start without this file.

  - Existing project: the installer fills this from what it detects + the
    bootstrap interview.
  - New project: leave the prompts for `/bootstrap`. Do not guess.

  Delete this comment block once populated.
-->

# Product

## What it is

{{One paragraph: what the product does and the problem it solves, in the
language a user (not an engineer) would use.}}

## Who uses it

{{The primary users and what they are trying to accomplish.}}

## Modules / experience

- {{module}} — {{what for}}

## What it is NOT

{{Explicit non-goals — boundaries that keep scope honest.}}
