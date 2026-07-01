# Parked

<!--
  The ONLY human-facing wait in the system, and it never stops the loop — only
  the individual task. An item is parked ONLY when it physically cannot proceed
  without an external resource the system does not have (an API key, a paid
  account). It is NOT for decisions — every decision is made autonomously by the
  Decision Engine. Format:

    ## TASK-142 export requires a Steam API key
    reason: missing_external_resource
    needs: STEAM_API_KEY in .env
    parked_at: 2026-06-30T14:02Z

  `groom` re-checks parked items each cycle and unparks them when the resource
  appears. Parked items are ignored by the phase decision (they never keep the
  loop from reaching `done`). Leave empty until something is genuinely parked.
-->
