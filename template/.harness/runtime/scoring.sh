#!/usr/bin/env bash
# scoring.sh — WSJF (Weighted Shortest Job First), the autonomous prioritizer.
#
#   WSJF = Cost of Delay / Job Duration
#   Cost of Delay = business_value + time_criticality + risk_reduction   (weighted)
#
# The four inputs are ESTIMATED by the groom/plan agents against concrete signals
# (module priority in PRODUCT.md, dependency out-degree, prod-bug vs long-term
# vision, gap-analysis size). This script only applies the arithmetic and the
# weights, which live once in .harness/specs/DECISION_POLICY.md — so priority is
# never renegotiated item by item.

: "${HARNESS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
POLICY_FILE="$HARNESS_DIR/specs/DECISION_POLICY.md"

# Read a `key: number` weight from the policy, with a default.
_policy_weight() {
  local key="$1" def="$2" v
  [[ -f "$POLICY_FILE" ]] || { printf '%s' "$def"; return; }
  v=$(grep -iE "^[[:space:]]*$key[[:space:]]*:" "$POLICY_FILE" 2>/dev/null | head -1 \
      | sed -E 's/.*:[[:space:]]*//; s/[^0-9.].*$//')
  [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]] && printf '%s' "$v" || printf '%s' "$def"
}

# wsjf_score <business_value> <time_criticality> <risk_reduction> <job_duration>
# Each estimate is clamped to the nearest Fibonacci value {1,2,3,5,8,13} — the
# rubric is enforced here, not just requested in prose, so an agent cannot
# smuggle false precision (e.g. 7.4) into the priority.
wsjf_score() {
  local bv="${1:-1}" tc="${2:-1}" rr="${3:-1}" dur="${4:-1}"
  local wbv wtc wrr
  wbv=$(_policy_weight business_value 1)
  wtc=$(_policy_weight time_criticality 1)
  wrr=$(_policy_weight risk_reduction 1)
  awk -v bv="$bv" -v tc="$tc" -v rr="$rr" -v dur="$dur" \
      -v wbv="$wbv" -v wtc="$wtc" -v wrr="$wrr" '
    function fib(n,   F,i,best,bd,d) {
      split("1 2 3 5 8 13", F, " "); best=1; bd=1e9
      for (i=1; i<=6; i++) { d = (n>F[i] ? n-F[i] : F[i]-n); if (d<bd) { bd=d; best=F[i] } }
      return best
    }
    BEGIN {
      bv=fib(bv); tc=fib(tc); rr=fib(rr); dur=fib(dur)
      cod = bv*wbv + tc*wtc + rr*wrr
      d = (dur < 1 ? 1 : dur)
      printf "%.1f", cod / d
    }'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    score) shift; wsjf_score "$@" ;;
    weight) shift; _policy_weight "$@" ;;
    *) echo "usage: scoring.sh score <bv> <tc> <rr> <dur> | weight <key> <default>" >&2; exit 2 ;;
  esac
fi
