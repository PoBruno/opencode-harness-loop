# Patterns

<!--
  Semantic memory: conventions that emerged and became rules. This is where the
  Distillation Engine watches for a repeated pattern (≥ 2 occurrences) that
  should graduate into a reusable skill.

    ## API handlers return Result<T, ApiError>, never throw
    All route handlers use the Result type; errors are values, not exceptions.
-->
