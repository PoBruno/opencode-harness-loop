#!/usr/bin/env bash
# events.sh — the Event Bus writer (append-only, one JSONL file per day).
#
# Every meaningful state transition publishes an event. The Presentation Layer
# (TUI, static HTML, notifiers) consumes these files and NEVER writes them.
# Only the runtime emits events; agents never publish directly — they change
# state, and the runtime translates the change into an event.
#
# Event schema (event is always "{domain}.{action}"):
#   { "ts", "event", "loop", "task", "result", "duration_ms", "data" }
#
# Usage:
#   source events.sh ; events_emit cycle.started --loop build
#   bash events.sh emit build.finished --loop build --task TASK-088 --result pass --duration_ms 41200

: "${HARNESS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
EVENTS_DIR="$HARNESS_DIR/events"

events_emit() {
  local event="$1"; shift || true
  [[ -n "$event" ]] || { echo "events_emit: event required" >&2; return 2; }

  local loop="" task="" result="" duration_ms="" data="{}"
  while (( $# )); do
    case "$1" in
      --loop)        loop="$2"; shift 2 ;;
      --task)        task="$2"; shift 2 ;;
      --result)      result="$2"; shift 2 ;;
      --duration_ms) duration_ms="$2"; shift 2 ;;
      --data)        data="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  mkdir -p "$EVENTS_DIR"
  local file="$EVENTS_DIR/$(date +%Y-%m-%d).jsonl"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if command -v jq >/dev/null 2>&1; then
    jq -cn \
      --arg ts "$ts" --arg event "$event" --arg loop "$loop" \
      --arg task "$task" --arg result "$result" \
      --argjson duration_ms "${duration_ms:-null}" \
      --argjson data "$data" \
      '{ts:$ts, event:$event,
        loop:(if $loop=="" then null else $loop end),
        task:(if $task=="" then null else $task end),
        result:(if $result=="" then null else $result end),
        duration_ms:$duration_ms, data:$data}
       | with_entries(select(.value != null))' >>"$file"
  else
    printf '{"ts":"%s","event":"%s","loop":"%s","task":"%s","result":"%s"}\n' \
      "$ts" "$event" "$loop" "$task" "$result" >>"$file"
  fi
}

# events_tail [n] — last n events across today's file (for quick inspection).
events_tail() {
  local n="${1:-20}"
  local file="$EVENTS_DIR/$(date +%Y-%m-%d).jsonl"
  [[ -f "$file" ]] && tail -n "$n" "$file" || true
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    emit) events_emit "$@" ;;
    tail) events_tail "$@" ;;
    *) echo "usage: events.sh {emit <event> [--loop L --task T --result R --duration_ms N --data JSON] | tail [n]}" >&2; exit 2 ;;
  esac
fi
