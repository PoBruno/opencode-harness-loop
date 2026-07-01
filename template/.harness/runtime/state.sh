#!/usr/bin/env bash
# state.sh — runtime state, contract enforcement, commit/rollback, phase decision.
#
# Sole writer of state/runtime.json and authority on:
#   - next_loop          which loop runs (deterministic; never an LLM)
#   - validate_contract  did the agent write only inside its declared scope
#   - commit / rollback  promote a validated cycle, or undo a failed one
#
# The ownership map mirrors each agent's `writes:` frontmatter and the Contracts
# table. Note the doctrine restriction: PARKED.md is the ONLY human-facing signal,
# and only for a missing external resource — no agent writes a decision request
# back. Everything else is decided by the Decision Engine (decide.sh).

: "${HARNESS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RUNTIME_DIR="$HARNESS_DIR/runtime"
STATE_DIR="$HARNESS_DIR/state"
SPECS_DIR="$HARNESS_DIR/specs"
INBOX_DIR="$HARNESS_DIR/inbox"
TASKS_DIR="$HARNESS_DIR/tasks"

RUNTIME_JSON="$STATE_DIR/runtime.json"
INBOX_FILE="$INBOX_DIR/inbox.md"
PARKED_FILE="$HARNESS_DIR/PARKED.md"
ROADMAP_FILE="$SPECS_DIR/ROADMAP.md"
SPRINT_FILE="$SPECS_DIR/SPRINT.md"

# shellcheck source=git.sh
source "$RUNTIME_DIR/git.sh"
# shellcheck source=events.sh
source "$RUNTIME_DIR/events.sh"

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
_count() {
  local pat="$1" file="$2" n
  [[ -f "$file" ]] || { printf '0'; return; }
  n=$(grep -cE "$pat" "$file" 2>/dev/null) || n=0
  printf '%s' "${n:-0}"
}

# INBOX items are raw dumps tagged by desk: "## [I-142] type: ..."
count_inbox_pending()   { _count '^##[[:space:]]+\[I-[0-9]+\]' "$INBOX_FILE"; }
count_parked()          { _count '^##[[:space:]]+' "$PARKED_FILE"; }
count_roadmap_pending() { _count '^##[[:space:]]+\[pending\]' "$ROADMAP_FILE"; }
count_roadmap_done()    { _count '^##[[:space:]]+\[done\]' "$ROADMAP_FILE"; }
count_roadmap_rejected(){ _count '^##[[:space:]]+\[auto-rejected\]' "$ROADMAP_FILE"; }
count_sprint_open()     { _count '^[[:space:]]*-[[:space:]]+\[[[:space:]]\]' "$SPRINT_FILE"; }
count_sprint_done()     { _count '^[[:space:]]*-[[:space:]]+\[[xX]\]' "$SPRINT_FILE"; }
# Two extra sprint states beyond open/done, both invisible to open/done counts:
#   [p] parked    — waiting on a missing external resource (runtime-marked)
#   [!] escalated — repeatedly failed; routed back to plan for a fresh decision
count_sprint_parked()    { _count '^[[:space:]]*-[[:space:]]+\[[pP]\]' "$SPRINT_FILE"; }
count_sprint_escalated() { _count '^[[:space:]]*-[[:space:]]+\[!\]' "$SPRINT_FILE"; }

current_task() {
  [[ -f "$SPRINT_FILE" ]] || return 0
  grep -m1 -E '^[[:space:]]*-[[:space:]]+\[[[:space:]]\]' "$SPRINT_FILE" 2>/dev/null \
    | grep -oE 'TASK-[0-9]+' | head -1 || true
}

# ---------------------------------------------------------------------------
# Phase decision. Drain intake, re-decide escalated tasks, deliver ready work,
# then plan more. Review and distill run inline after build (in cycle.sh).
# Sprint tasks in [p] (parked) or [!] (escalated) are invisible to open/done, so
# a stuck task never blocks the ones behind it — the loop keeps flowing.
# ---------------------------------------------------------------------------
next_loop() {
  (( $(count_inbox_pending) > 0 ))     && { echo groom; return; }
  (( $(count_sprint_escalated) > 0 ))  && { echo planner; return; }
  (( $(count_sprint_open) > 0 ))       && { echo build; return; }
  (( $(count_roadmap_pending) > 0 ))   && { echo planner; return; }
  echo idle
}

# ---------------------------------------------------------------------------
# runtime.json (sole writer)
# ---------------------------------------------------------------------------
state_init() {
  mkdir -p "$STATE_DIR"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg ts "$ts" '{
    schema: 2, pid: 0, cycle: 0, active_loop: "none", current_task: "",
    last_review: "", health: "green", consecutive_failures: 0,
    consecutive_sterile: 0, message: "", started_at: $ts, updated_at: $ts
  }' >"$RUNTIME_JSON"
}

state_set() {
  [[ -f "$RUNTIME_JSON" ]] || state_init
  local json; json="$(cat "$RUNTIME_JSON")"
  while (( $# >= 2 )); do
    local k="$1" v="$2"; shift 2
    if [[ "$v" =~ ^-?[0-9]+$ ]]; then
      json="$(jq --arg k "$k" --argjson v "$v" '.[$k]=$v' <<<"$json")"
    else
      json="$(jq --arg k "$k" --arg v "$v" '.[$k]=$v' <<<"$json")"
    fi
  done
  json="$(jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.updated_at=$ts' <<<"$json")"
  printf '%s\n' "$json" >"$RUNTIME_JSON.tmp" && mv "$RUNTIME_JSON.tmp" "$RUNTIME_JSON"
}

state_get() { jq -r --arg k "$1" '.[$k] // empty' "$RUNTIME_JSON" 2>/dev/null; }
interval() { printf '%s' "${HARNESS_INTERVAL:-5}"; }

# ---------------------------------------------------------------------------
# Contract enforcement. Explicit allow prefixes are checked FIRST so a specific
# allow (e.g. build -> .harness/PARKED.md) overrides a broad deny (.harness/).
# ---------------------------------------------------------------------------
_contract_allow() {
  case "$1" in
    desk)    echo ".harness/inbox/inbox.md" ;;
    groom)   echo ".harness/specs/ROADMAP.md .harness/memory/intent.jsonl .harness/inbox/ .harness/PARKED.md" ;;
    planner) echo ".harness/specs/SPRINT.md .harness/specs/ROADMAP.md .harness/tasks/ .harness/memory/decisions.md .harness/memory/assumptions.md .harness/PARKED.md" ;;
    build)   echo ".harness/PARKED.md *" ;;
    review)  echo ".harness/memory/ .harness/state/understanding.json" ;;
    distill) echo ".harness/skills/ .harness/mcp/" ;;
    *)       echo "" ;;
  esac
}
_contract_deny() {
  case "$1" in
    build) echo ".harness/" ;;
    *)     echo "" ;;
  esac
}
_prefix_match() { [[ "$1" == "$2"* ]]; }

contract_allows() {
  local loop="$1" file="$2" p
  local allow deny; allow="$(_contract_allow "$loop")"; deny="$(_contract_deny "$loop")"
  for p in $allow; do [[ "$p" == "*" ]] && continue; _prefix_match "$file" "$p" && return 0; done
  for p in $deny; do _prefix_match "$file" "$p" && return 1; done
  [[ " $allow " == *" * "* ]] && return 0
  return 1
}

# Semantic guard on PARKED.md: EVERY top-level `## ` item must declare
# `reason: missing_external_resource`. This is the technical lock behind the
# "never ask the human" doctrine — an agent cannot smuggle a decision request
# into PARKED by inventing another reason; the runtime rolls the cycle back.
# (Indented example blocks inside the header comment are not `^## `, so ignored.)
validate_parked_reasons() {
  [[ -f "$PARKED_FILE" ]] || return 0
  awk '
    /^## / { if (inblock && !ok) bad=1; inblock=1; ok=0; next }
    inblock && /^reason:[[:space:]]*missing_external_resource[[:space:]]*$/ { ok=1 }
    END { if (inblock && !ok) bad=1; exit (bad ? 1 : 0) }
  ' "$PARKED_FILE"
}

# Every agent-authored mcp/*/mcp.json must stay `status: quarantine`. Promoting a
# network tool (status: approved + registration in opencode.json) is a human-only
# action — this rejects any agent trying to self-approve.
validate_mcp_quarantine() {
  local f
  shopt -s nullglob
  for f in "$HARNESS_DIR"/mcp/*/mcp.json; do
    if ! grep -qE '"status"[[:space:]]*:[[:space:]]*"quarantine"' "$f"; then
      shopt -u nullglob; return 1
    fi
  done
  shopt -u nullglob
  return 0
}

validate_contract() {
  local loop="$1" f bad=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if ! contract_allows "$loop" "$f"; then
      echo "contract violation: $loop wrote out-of-scope file: $f" >&2
      bad=1
    fi
    if [[ "$f" == ".harness/PARKED.md" ]] && ! validate_parked_reasons; then
      echo "contract violation: $loop parked a task without 'reason: missing_external_resource' (decision requests are forbidden)" >&2
      bad=1
    fi
    if [[ "$f" == .harness/mcp/*/mcp.json ]] && ! validate_mcp_quarantine; then
      echo "contract violation: $loop generated/edited an MCP not in 'status: quarantine' (agents never self-approve network tools)" >&2
      bad=1
    fi
  done < <(git_changed_since_snapshot "$loop")
  return $bad
}

# commit_cycle <loop> <task> [paths...]
# With no paths, git_commit stages everything (git add -A) — correct for the Main
# Loop, whose agent (build) may write code anywhere. With paths, only those are
# staged — used by the intake watcher (`desk` only owns the inbox) so it can never
# sweep another writer's uncommitted work under a "desk" commit.
commit_cycle() {
  local loop="$1" task="${2:-}"
  shift 2 2>/dev/null || true
  git_commit "harness($loop): cycle $(state_get cycle)${task:+ $task}" "$@"
}
rollback_cycle() { git_rollback "${1:-}"; }

# ---- runtime-owned sprint mutations (agents cannot flip these checkboxes) ---
_flip_first_open() { # <new-marker, e.g. x | p | !>
  [[ -f "$SPRINT_FILE" ]] || return 0
  awk -v m="$1" '!d && /^[[:space:]]*-[[:space:]]+\[[[:space:]]\]/ { sub(/\[[[:space:]]\]/, "[" m "]"); d=1 } { print }' \
    "$SPRINT_FILE" >"$SPRINT_FILE.tmp" && mv "$SPRINT_FILE.tmp" "$SPRINT_FILE"
}
mark_first_task_parked()    { _flip_first_open p; }
mark_first_task_escalated() { _flip_first_open '!'; }

# Drop the first escalated ([!]) task line (last-resort unstick for a stuck planner).
drop_first_escalated_task() {
  [[ -f "$SPRINT_FILE" ]] || return 0
  awk 'BEGIN{d=0} d==0 && /^[[:space:]]*-[[:space:]]+\[!\]/ { d=1; next } { print }' \
    "$SPRINT_FILE" >"$SPRINT_FILE.tmp" && mv "$SPRINT_FILE.tmp" "$SPRINT_FILE"
}

# Auto-reject the first pending roadmap item (bounded runtime fallback when plan
# cannot decompose it after repeated stalls).
reject_first_roadmap_pending() {
  [[ -f "$ROADMAP_FILE" ]] || return 0
  awk '!d && /^##[[:space:]]+\[pending\]/ { sub(/\[pending\]/,"[auto-rejected]"); d=1 } { print }' \
    "$ROADMAP_FILE" >"$ROADMAP_FILE.tmp" && mv "$ROADMAP_FILE.tmp" "$ROADMAP_FILE"
}

# Drop the first INBOX item (unstick a groom looping on a malformed dump).
drop_first_inbox_item() {
  [[ -f "$INBOX_FILE" ]] || return 0
  awk 'BEGIN{drop=0;done=0}
       /^##[[:space:]]+\[I-/ { if(!done){drop=1;done=1;next} }
       /^## / { if(drop) drop=0 }
       { if(!drop) print }' \
    "$INBOX_FILE" >"$INBOX_FILE.tmp" && mv "$INBOX_FILE.tmp" "$INBOX_FILE"
}

# Re-sync SPRINT with PARKED: any [p] task whose id no longer appears in
# PARKED.md is un-parked back to [ ] (the resource returned). Called after groom.
reconcile_sprint_parked() {
  [[ -f "$SPRINT_FILE" ]] || return 0
  local ids=" "
  [[ -f "$PARKED_FILE" ]] && ids=" $(grep -oE 'TASK-[0-9]+' "$PARKED_FILE" 2>/dev/null | sort -u | tr '\n' ' ')"
  awk -v ids="$ids" '
    /^[[:space:]]*-[[:space:]]+\[[pP]\]/ {
      line=$0
      if (match(line, /TASK-[0-9]+/)) {
        id=substr(line, RSTART, RLENGTH)
        if (index(ids, " " id " ") == 0) sub(/\[[pP]\]/, "[ ]")
      }
    }
    { print }' \
    "$SPRINT_FILE" >"$SPRINT_FILE.tmp" && mv "$SPRINT_FILE.tmp" "$SPRINT_FILE"
}

mark_first_task_done() {
  [[ -f "$SPRINT_FILE" ]] || return 0
  awk '!done && /^[[:space:]]*-[[:space:]]+\[[[:space:]]\]/ { sub(/\[[[:space:]]\]/,"[x]"); done=1 } { print }' \
    "$SPRINT_FILE" >"$SPRINT_FILE.tmp" && mv "$SPRINT_FILE.tmp" "$SPRINT_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    init) state_init ;;
    set) state_set "$@" ;;
    get) state_get "$@" ;;
    next_loop) next_loop ;;
    current_task) current_task ;;
    interval) interval ;;
    validate_contract) validate_contract "$@" ;;
    validate_parked) validate_parked_reasons && echo "parked: ok" || { echo "parked: bad reason" >&2; exit 1; } ;;
    validate_mcp) validate_mcp_quarantine && echo "mcp: ok" || { echo "mcp: not quarantined" >&2; exit 1; } ;;
    commit) commit_cycle "$@" ;;
    rollback) rollback_cycle "$@" ;;
    mark_done) mark_first_task_done ;;
    mark_parked) mark_first_task_parked ;;
    mark_escalated) mark_first_task_escalated ;;
    drop_escalated) drop_first_escalated_task ;;
    reject_roadmap) reject_first_roadmap_pending ;;
    drop_inbox) drop_first_inbox_item ;;
    reconcile_parked) reconcile_sprint_parked ;;
    counters)
      printf 'inbox=%s parked=%s sprint_open=%s sprint_done=%s sprint_parked=%s sprint_escalated=%s roadmap_pending=%s roadmap_done=%s rejected=%s\n' \
        "$(count_inbox_pending)" "$(count_parked)" "$(count_sprint_open)" "$(count_sprint_done)" \
        "$(count_sprint_parked)" "$(count_sprint_escalated)" \
        "$(count_roadmap_pending)" "$(count_roadmap_done)" "$(count_roadmap_rejected)" ;;
    *) echo "usage: state.sh {init|set|get|next_loop|current_task|interval|validate_contract L|validate_parked|validate_mcp|commit L [t]|rollback|mark_done|mark_parked|mark_escalated|drop_escalated|reject_roadmap|drop_inbox|reconcile_parked|counters}" >&2; exit 2 ;;
  esac
fi
