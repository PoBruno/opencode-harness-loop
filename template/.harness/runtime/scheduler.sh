#!/usr/bin/env bash
# scheduler.sh — bootstrap + supervisor entrypoint.
#
# Two ways in, same runtime underneath:
#   scheduler.sh --bootstrap     headless (cron, CI, SSH without a TTY)
#   (the Textual TUI launches this same command when the runtime is down)
#
# Bootstrap: zero the state, require specs/PRODUCT.md, create the inbox and
# event files, spawn the half-loop watcher, then run the Main Loop (cycle.sh).
#
# Flags: --once (single cycle), --daemon (keep waiting on idle), --no-intake
#        (skip the half-loop watcher), --reset (re-zero runtime.json), --help.

set -uo pipefail

RUNTIME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$RUNTIME_DIR/.." && pwd)"
export HARNESS_DIR

# shellcheck source=state.sh
source "$RUNTIME_DIR/state.sh"

BOOTSTRAP=0; ONCE=0; NO_INTAKE=0; RESET=0
export HARNESS_DAEMON="${HARNESS_DAEMON:-0}"

usage() { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while (( $# )); do
  case "$1" in
    --bootstrap) BOOTSTRAP=1 ;;
    --once)      ONCE=1 ;;
    --daemon)    export HARNESS_DAEMON=1 ;;
    --no-intake) NO_INTAKE=1 ;;
    --reset)     RESET=1 ;;
    --help|-h)   usage; exit 0 ;;
    *) echo "unknown flag: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

prereq_check() {
  local missing=()
  for t in git jq md5sum date awk; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
  (( ${#missing[@]} > 0 )) && { echo "missing prerequisites: ${missing[*]}" >&2; exit 1; }
  command -v opencode >/dev/null 2>&1 || echo "WARN: opencode not on PATH — agents will fail to launch" >&2
}

ensure_dirs() {
  mkdir -p "$HARNESS_DIR"/{specs,inbox/triaged,inbox/incoming/processed,tasks,state,memory/history,events,logs,skills,mcp}
}

INTAKE_PID=""
cleanup() { [[ -n "$INTAKE_PID" ]] && kill "$INTAKE_PID" 2>/dev/null || true; }

main() {
  prereq_check
  ensure_dirs

  # require the product spec — the runtime has nothing to build without it
  if [[ ! -f "$HARNESS_DIR/specs/PRODUCT.md" ]]; then
    echo "abort: $HARNESS_DIR/specs/PRODUCT.md is missing (run /bootstrap first)" >&2
    exit 1
  fi

  # safety nudge: invariants are the only absolute veto. If they are still
  # placeholders, full autonomy runs with no guardrail beyond the technical gates.
  local arch="$HARNESS_DIR/specs/ARCHITECTURE.md"
  if [[ -f "$arch" ]] && grep -qE '^##[[:space:]]+Invariants' "$arch"; then
    if awk '/^##[[:space:]]+Invariants/{f=1;next} /^##[[:space:]]/{f=0} f' "$arch" | grep -q '{{'; then
      echo "WARN: ARCHITECTURE.md invariants are still placeholders — the autonomous loop has NO absolute veto. Fill them (see /bootstrap) before unsupervised runs." >&2
    fi
  else
    echo "WARN: ARCHITECTURE.md has no Invariants section — the autonomous loop has no absolute veto." >&2
  fi

  # safety nudge: WSJF weights are the only structural priority input. Warn if the
  # policy is missing or still neutral (1/1/1) — priority would be undifferentiated.
  local policy="$HARNESS_DIR/specs/DECISION_POLICY.md"
  if [[ ! -f "$policy" ]]; then
    echo "WARN: DECISION_POLICY.md is missing — WSJF defaults to 1/1/1 (no real priority)." >&2
  else
    local bv tc rr
    bv=$(bash "$RUNTIME_DIR/scoring.sh" weight business_value 1)
    tc=$(bash "$RUNTIME_DIR/scoring.sh" weight time_criticality 1)
    rr=$(bash "$RUNTIME_DIR/scoring.sh" weight risk_reduction 1)
    if [[ "$bv" == "1" && "$tc" == "1" && "$rr" == "1" ]]; then
      echo "WARN: DECISION_POLICY.md WSJF weights are still 1/1/1 — tune them at /bootstrap so priority is real." >&2
    fi
  fi

  [[ -f "$HARNESS_DIR/state/runtime.json" && "$RESET" -eq 0 ]] || state_init
  [[ -f "$HARNESS_DIR/inbox/inbox.md" ]]   || printf '# Inbox\n' >"$HARNESS_DIR/inbox/inbox.md"
  [[ -f "$HARNESS_DIR/PARKED.md" ]]        || printf '# Parked\n' >"$HARNESS_DIR/PARKED.md"
  touch "$HARNESS_DIR/events/$(date +%Y-%m-%d).jsonl"

  if (( NO_INTAKE == 0 )); then
    if command -v setsid >/dev/null 2>&1; then
      setsid bash "$RUNTIME_DIR/intake_loop.sh" >/dev/null 2>&1 &
    else
      bash "$RUNTIME_DIR/intake_loop.sh" >/dev/null 2>&1 &
    fi
    INTAKE_PID=$!
    trap cleanup EXIT
  fi

  local max="${MAX_ITERATIONS:-100}"
  (( ONCE == 1 )) && max=1
  MAX_ITERATIONS="$max" bash "$RUNTIME_DIR/cycle.sh"
}

main
