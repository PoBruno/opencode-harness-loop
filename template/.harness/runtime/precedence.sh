#!/usr/bin/env bash
# precedence.sh — the conflict-resolution hierarchy.
#
# When two sources of truth appear to contradict, the system climbs a fixed,
# ordered chain until the first criterion breaks the tie — mechanically, never
# by asking. The order is defined once (here and in AGENTS.md):
#
#   1. invariant            architecture invariants (security, data integrity) — absolute veto
#   2. decision_recent      the most recent superseding decision in decisions.md
#   3. wsjf                 the higher calculated WSJF wins over implicit priority
#   4. reversibility        prefer the option that is cheaper to undo (two-way door)
#   5. diff_size            the smaller change, when options are otherwise equal in risk
#
# Agents identify which criterion each side of a conflict rests on and call
# precedence_winner to get the deterministic verdict.

precedence_chain() {
  cat <<'EOF'
1 invariant
2 decision_recent
3 wsjf
4 reversibility
5 diff_size
EOF
}

precedence_rank() {
  case "$1" in
    invariant)        echo 1 ;;
    decision_recent)  echo 2 ;;
    wsjf)             echo 3 ;;
    reversibility)    echo 4 ;;
    diff_size)        echo 5 ;;
    *)                echo 99 ;;
  esac
}

# precedence_winner <side_a_criterion> <side_b_criterion>
# Prints the criterion that wins (lower rank). Ties print "tie".
precedence_winner() {
  local ra rb
  ra=$(precedence_rank "$1")
  rb=$(precedence_rank "$2")
  if (( ra < rb )); then printf '%s' "$1"
  elif (( rb < ra )); then printf '%s' "$2"
  else printf 'tie'; fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    chain)  precedence_chain ;;
    rank)   precedence_rank "${2:-}" ;;
    winner) precedence_winner "${2:-}" "${3:-}" ;;
    *) echo "usage: precedence.sh {chain | rank <criterion> | winner <a> <b>}" >&2; exit 2 ;;
  esac
fi
