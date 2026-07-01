#!/usr/bin/env bash
# context.sh — the Context Engine. Assembles state/working_context.json each
# cycle: only what the loop needs (the current task, the relevant slice of
# ARCHITECTURE, the last few decisions), never the whole repo. The token budget
# is a contract, not a suggestion.

: "${HARNESS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RUNTIME_DIR="$HARNESS_DIR/runtime"
STATE_DIR="$HARNESS_DIR/state"
SPECS_DIR="$HARNESS_DIR/specs"
INBOX_DIR="$HARNESS_DIR/inbox"
TASKS_DIR="$HARNESS_DIR/tasks"
MEMORY_DIR="$HARNESS_DIR/memory"

WORKING_CONTEXT="$STATE_DIR/working_context.json"
UNDERSTANDING="$STATE_DIR/understanding.json"

# shellcheck source=state.sh
source "$RUNTIME_DIR/state.sh"

: "${HARNESS_TOKEN_BUDGET:=8000}"
: "${HARNESS_ARCH_CHARS:=6000}"

_slurp()      { [[ -f "$1" ]] && cat "$1" || printf ''; }
_slurp_head() { [[ -f "$1" ]] && head -c "${2:-4000}" "$1" || printf ''; }

context_build() {
  local loop="$1"
  mkdir -p "$STATE_DIR"

  local task_id task_file task_content=""
  task_id="$(current_task)"
  if [[ -n "$task_id" && -f "$TASKS_DIR/$task_id.md" ]]; then
    task_file="$TASKS_DIR/$task_id.md"
    task_content="$(_slurp "$task_file")"
  fi

  local arch invariants decisions_excerpt sprint inbox blocked understanding intake_msg
  arch="$(_slurp_head "$SPECS_DIR/ARCHITECTURE.md" "$HARNESS_ARCH_CHARS")"
  # The Invariants section is the only absolute veto — extract it in FULL so a
  # truncated architecture excerpt can never drop it.
  invariants="$(awk '/^##[[:space:]]+Invariants/{f=1;print;next} /^##[[:space:]]/{f=0} f{print}' "$SPECS_DIR/ARCHITECTURE.md" 2>/dev/null || true)"
  decisions_excerpt="$(_slurp "$MEMORY_DIR/decisions.md" | tail -n 80)"
  understanding="$(_slurp "$UNDERSTANDING")"
  [[ -z "$understanding" ]] && understanding="{}"

  # Per-loop extras kept lean.
  intake_msg=""
  case "$loop" in
    desk)  sprint=""; inbox="$(_slurp "$INBOX_DIR/inbox.md")"; blocked="$(_slurp "$HARNESS_DIR/PARKED.md")"
           intake_msg="$(_slurp "$STATE_DIR/intake_message.txt")" ;;
    groom) sprint=""; inbox="$(_slurp "$INBOX_DIR/inbox.md")"; blocked="$(_slurp "$HARNESS_DIR/PARKED.md")" ;;
    plan)  sprint="$(_slurp "$SPECS_DIR/SPRINT.md")"; inbox="$(_slurp "$INBOX_DIR/inbox.md")"; blocked="" ;;
    *)     sprint="$(_slurp "$SPECS_DIR/SPRINT.md")"; inbox=""; blocked="" ;;
  esac

  jq -n \
    --arg loop "$loop" \
    --arg task_id "${task_id:-}" \
    --arg task "$task_content" \
    --arg architecture_excerpt "$arch" \
    --arg invariants "$invariants" \
    --arg intake_message "$intake_msg" \
    --arg decisions "$decisions_excerpt" \
    --arg sprint "$sprint" \
    --arg inbox "$inbox" \
    --arg parked "$blocked" \
    --argjson understanding "$understanding" \
    --argjson token_budget "$HARNESS_TOKEN_BUDGET" \
    '{
      loop: $loop,
      task_id: $task_id,
      task: $task,
      architecture_excerpt: $architecture_excerpt,
      invariants: $invariants,
      intake_message: $intake_message,
      recent_decisions: ($decisions | split("## ") | map(select(length > 0)) | (.[-5:] // [])),
      sprint: $sprint,
      inbox: $inbox,
      parked: $parked,
      understanding: $understanding,
      token_budget: $token_budget
    }' >"$WORKING_CONTEXT.tmp" && mv "$WORKING_CONTEXT.tmp" "$WORKING_CONTEXT"

  # The intake message is a one-shot handoff — clear it once folded into context
  # so the next desk run does not reprocess a stale message.
  [[ "$loop" == desk && -f "$STATE_DIR/intake_message.txt" ]] && : >"$STATE_DIR/intake_message.txt"

  printf '%s\n' "$WORKING_CONTEXT"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    build) context_build "$@" ;;
    *) echo "usage: context.sh build <loop>" >&2; exit 2 ;;
  esac
fi
