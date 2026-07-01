#!/usr/bin/env bash
# memory.sh — the Memory Engine. Owner of the episodic layer (append-only).
#
# CoALA layering:
#   working   -> state/working_context.json   (Context Engine, 1 cycle)
#   episodic  -> memory/history/*.jsonl        (this file, append-only, raw)
#   semantic  -> memory/decisions.md, learnings.md, patterns.md (Review curates)
#   procedural-> agents, skills/               (humans + Distillation)
#
# The episodic→semantic transformation (consolidation) is the Review agent's
# job; this engine only records the raw trail. Without consolidation, semantic
# memory rots into a dump of raw logs — the most common harness mistake.

: "${HARNESS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HISTORY_DIR="$HARNESS_DIR/memory/history"
LEARNINGS_FILE="$HARNESS_DIR/memory/learnings.md"

# memory_log <loop> <result> [logfile] — append one episodic event.
memory_log() {
  local loop="$1" result="${2:-}" logfile="${3:-}"
  mkdir -p "$HISTORY_DIR"
  local file="$HISTORY_DIR/$(date +%Y-%m-%d).jsonl"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$ts" --arg loop "$loop" --arg result "$result" --arg log "$logfile" \
      '{ts:$ts, loop:$loop, result:$result, log:(if $log=="" then null else $log end)}
       | with_entries(select(.value!=null))' >>"$file"
  else
    printf '{"ts":"%s","loop":"%s","result":"%s"}\n' "$ts" "$loop" "$result" >>"$file"
  fi
}

# memory_log_incident <loop> <detail> — an aborted/failed cycle. Recorded in the
# episodic log and surfaced as a one-line learning ("what broke").
memory_log_incident() {
  local loop="$1" detail="${2:-incident}"
  memory_log "$loop" "incident"
  mkdir -p "$(dirname "$LEARNINGS_FILE")"
  [[ -f "$LEARNINGS_FILE" ]] || printf '# Learnings\n' >"$LEARNINGS_FILE"
  printf -- '- _(incident %s)_ %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$loop" "$detail" >>"$LEARNINGS_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    log)          memory_log "$@" ;;
    log_incident) memory_log_incident "$@" ;;
    *) echo "usage: memory.sh {log <loop> <result> [logfile] | log_incident <loop> <detail>}" >&2; exit 2 ;;
  esac
fi
