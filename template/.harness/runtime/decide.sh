#!/usr/bin/env bash
# decide.sh — the Decision Engine dispatcher.
#
# Every point that used to write `ask:` back to the human now consults one of the
# four mechanisms here. This script NEVER writes prose — it applies a rule and
# returns a structured verdict the calling agent folds into its own reasoning,
# and it publishes decision.* events to the bus for the Decision Log.
#
#   decide.sh wsjf <bv> <tc> <rr> <dur>    -> a priority number (WSJF)
#   decide.sh door "<change description>"  -> "one-way" | "two-way"
#   decide.sh precedence <a> <b>           -> the winning criterion
#   decide.sh event <decision.event> ...   -> publish a decision/task event
#
# Doctrine: one-way (irreversible/expensive) demands HIGH confidence and prefers
# the reversible slice; two-way (cheap to undo) decides fast on the additive
# default. The agent enforces that; this classifies.

RUNTIME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${HARNESS_DIR:=$(cd "$RUNTIME_DIR/.." && pwd)}"

# shellcheck source=scoring.sh
source "$RUNTIME_DIR/scoring.sh"
# shellcheck source=precedence.sh
source "$RUNTIME_DIR/precedence.sh"
# shellcheck source=events.sh
source "$RUNTIME_DIR/events.sh"

# Classify a change as a one-way (irreversible/costly) or two-way (reversible)
# door by scanning the description for irreversibility signals.
door_classify() {
  local text
  text="$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]')"
  local oneway='drop |drop-|delete |remove |destroy|destructive|truncate|purge|wipe|breaking change|break api|public api|contract change|schema migration|migrate schema|data loss|irreversible|rename column|drop column|drop table'
  if printf '%s' "$text" | grep -qE "$oneway"; then
    echo "one-way"
  else
    echo "two-way"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    wsjf)       wsjf_score "$@" ;;
    door)       door_classify "$@" ;;
    precedence) precedence_winner "${1:-}" "${2:-}" ;;
    event)
      ev="${1:-}"; shift || true
      case "$ev" in
        decision.*|task.parked|task.unparked|task.decomposed) events_emit "$ev" "$@" ;;
        *) echo "decide.sh event: only decision.* / task.parked|unparked|decomposed allowed" >&2; exit 2 ;;
      esac
      ;;
    *) echo "usage: decide.sh {wsjf <bv> <tc> <rr> <dur> | door <text> | precedence <a> <b> | event <decision.event> ...}" >&2; exit 2 ;;
  esac
fi
