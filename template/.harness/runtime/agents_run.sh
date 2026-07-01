#!/usr/bin/env bash
# agents_run.sh — the bridge between the runtime and the executor (opencode).
#
# Given a loop name and a working-context file, it launches the matching agent
# under session isolation (setsid + timeout), captures the trajectory to a log,
# and returns the executor's exit code. The agent's behaviour lives in its
# .opencode/agent/<name>.md definition; this only tells it to run one cycle.
#
# Source it to get the agents_run() function (so the caller can manage the PID
# and traps), or run it directly as a CLI.

: "${HARNESS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT_DIR="$(cd "$HARNESS_DIR/.." && pwd)"

: "${PHASE_TIMEOUT:=30m}"
: "${HARNESS_MODEL:=}"

AGENT_PID=""   # exported for the caller's interrupt trap

_agent_prompt() {
  local loop="$1"
  local base="Read .harness/state/working_context.json for your inputs, then run EXACTLY ONE ${loop} cycle now, following your agent instructions and AGENTS.md. Write only within your declared scope."
  case "$loop" in
    build) printf '%s %s' "$base" "Run the gates serially before finishing. End with one marker on its own line: RALPH_DONE (success), RALPH_BLOCKED (cannot finish), or RALPH_ALL_DONE (no open tasks). Also print 'RESULT: pass' or 'RESULT: fail'." ;;
    *)     printf '%s %s' "$base" "End with one line: 'RESULT: pass' on success or 'RESULT: fail' if you could not complete." ;;
  esac
}

agents_run() {
  local loop="$1" ctx="${2:-}" logfile="${3:-/dev/stdout}"
  export AR_AGENT="$loop"
  export AR_PROMPT="$(_agent_prompt "$loop")"
  export AR_TIMEOUT="$PHASE_TIMEOUT"
  export AR_MODEL="$HARNESS_MODEL"

  local launcher=()
  command -v setsid >/dev/null 2>&1 && launcher=(setsid)

  ( cd "$PROJECT_DIR" && "${launcher[@]}" bash -c '
      args=(run --agent "$AR_AGENT")
      [ -n "$AR_MODEL" ] && args+=(--model "$AR_MODEL")
      args+=("$AR_PROMPT")
      if command -v timeout >/dev/null 2>&1; then
        timeout -k 10 "$AR_TIMEOUT" opencode "${args[@]}"
      else
        opencode "${args[@]}"
      fi
    ' ) >"$logfile" 2>&1 &

  AGENT_PID=$!
  local gpid="$AGENT_PID"
  wait "$AGENT_PID"
  local rc=$?
  # Sweep any lingering members of the agent's process group — a timeout kills
  # the opencode process but its subagents could otherwise be orphaned. setsid
  # made gpid the session/group leader, so -gpid targets the whole group.
  kill -TERM -"$gpid" 2>/dev/null || true
  AGENT_PID=""
  return $rc
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  agents_run "$@"
fi
