#!/usr/bin/env bash
# intake_loop.sh — the Half Loop. Low-frequency, conversational, human-triggered.
#
# The primary way to talk to intake is interactively: `opencode --agent intake`.
# This background watcher is the non-interactive half-loop: when a message file
# is dropped into .harness/inbox/incoming/, it runs the desk agent on it
# (which may write inbox.md), then archives the message. It never
# consumes a Main-Loop cycle.

set -uo pipefail

RUNTIME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$RUNTIME_DIR/.." && pwd)"
export HARNESS_DIR

INCOMING_DIR="$HARNESS_DIR/inbox/incoming"
PROCESSED_DIR="$INCOMING_DIR/processed"
MESSAGE_HANDOFF="$HARNESS_DIR/state/intake_message.txt"

# shellcheck source=events.sh
source "$RUNTIME_DIR/events.sh"
# shellcheck source=context.sh
source "$RUNTIME_DIR/context.sh"
# shellcheck source=agents_run.sh
source "$RUNTIME_DIR/agents_run.sh"

: "${INTAKE_INTERVAL:=2}"

main() {
  mkdir -p "$INCOMING_DIR" "$PROCESSED_DIR"
  while true; do
    shopt -s nullglob
    local msg
    for msg in "$INCOMING_DIR"/*.md; do
      events_emit intake.message_received --data "$(jq -cn --arg f "$(basename "$msg")" '{file:$f}' 2>/dev/null || echo '{}')"
      cp "$msg" "$MESSAGE_HANDOFF"
      context_build desk >/dev/null
      local log="$HARNESS_DIR/logs/intake-$(date +%s).log"
      agents_run desk "$HARNESS_DIR/state/working_context.json" "$log" || true
      mv "$msg" "$PROCESSED_DIR/$(date +%s)-$(basename "$msg")" 2>/dev/null || true
    done
    shopt -u nullglob
    sleep "$INTAKE_INTERVAL"
  done
}

main "$@"
