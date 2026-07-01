# Sprint

<!--
  The executable plan for the current roadmap item. Planner writes; build reads.
  Tasks are markdown checkboxes tied to a detail file in .harness/tasks/. Four
  states (described, NOT drawn here, so this template is not miscounted — a list
  item whose checkbox holds a space/x/p/! marker):

    open      — an empty checkbox; build implements it next.
    done      — an "x" in the checkbox; implemented and passed review.
    parked    — a "p" in the checkbox; waiting on a missing external resource,
                SKIPPED by build. Runtime-owned: build/groom cannot flip it, so the
                runtime marks parked on a block and un-parks (open) on recheck.
    escalated — a "!" in the checkbox; failed/stalled repeatedly, routed back to
                `plan` to re-decide (smaller slice / reinterpret / auto-reject).

  Only the open state feeds build; parked and escalated are invisible to the
  open/done counts, so a stuck task never blocks the ones behind it. Tasks group
  under a "## R-{n}" heading. The planner may regenerate this document from
  scratch. Leave empty until the planner fills it.
-->
