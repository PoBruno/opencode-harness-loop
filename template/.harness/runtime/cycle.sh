#!/usr/bin/env bash
# cycle.sh — the Main Loop (the goal-loop core). Pure shell, zero token.
#
# Each cycle: decide the loop, build context, snapshot, run the agent under
# isolation, validate its contract, then commit (and inline-run review +
# distill after a build) or roll back. Sterile-change and consecutive-failure
# breakers transition health green -> yellow -> red; on red the runtime stops
# honestly (there is no human-decision block). Two traps keep the dashboard honest.

set -uo pipefail

RUNTIME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$RUNTIME_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
export HARNESS_DIR
LOGS_DIR="$HARNESS_DIR/logs"
WORKING_CONTEXT="$HARNESS_DIR/state/working_context.json"

# shellcheck source=state.sh
source "$RUNTIME_DIR/state.sh"
# shellcheck source=context.sh
source "$RUNTIME_DIR/context.sh"
# shellcheck source=memory.sh
source "$RUNTIME_DIR/memory.sh"
# shellcheck source=agents_run.sh
source "$RUNTIME_DIR/agents_run.sh"

: "${MAX_ITERATIONS:=100}"
: "${PHASE_TIMEOUT:=30m}"
: "${MAX_FAILURES:=3}"
: "${MAX_STERILE:=2}"
: "${HARNESS_DAEMON:=0}"
: "${PARKED_RECHECK:=10}"    # daemon: recheck parked items every N idle ticks

CYCLE=0
FAILURES=0
STERILE=0
IDLE_TICKS=0
LAST_HEALTH=""

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  log "FATAL: $*"
  state_set health red message "$*"
  _emit_health_change red
  generate_dashboard
  exit 1
}

fingerprint() {
  {
    git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo "no-head"
    git -C "$PROJECT_DIR" diff HEAD -- . \
      ':(exclude).harness/state' ':(exclude).harness/events' ':(exclude).harness/logs' 2>/dev/null || true
    git -C "$PROJECT_DIR" ls-files --others --exclude-standard -z 2>/dev/null \
      | while IFS= read -r -d '' f; do
          case "$f" in .harness/state/*|.harness/events/*|.harness/logs/*) continue;; esac
          printf '%s\0' "$f"; md5sum "$PROJECT_DIR/$f" 2>/dev/null || true
        done
  } | md5sum | awk '{print $1}'
}

classify_result() {
  local loop="$1" logfile="$2" rc="$3"
  (( rc == 124 || rc == 137 )) && { echo timeout; return; }
  if [[ "$loop" == build ]]; then
    grep -q 'RALPH_ALL_DONE' "$logfile" 2>/dev/null && { echo alldone; return; }
    grep -q 'RALPH_BLOCKED'  "$logfile" 2>/dev/null && { echo blocked; return; }
    grep -q 'RALPH_DONE'     "$logfile" 2>/dev/null && { echo pass; return; }
    grep -qiE 'RESULT:[[:space:]]*pass' "$logfile" 2>/dev/null && { echo pass; return; }
    echo fail-nosignal; return
  fi
  grep -qiE 'RESULT:[[:space:]]*fail' "$logfile" 2>/dev/null && { echo fail; return; }
  grep -qiE 'RESULT:[[:space:]]*pass' "$logfile" 2>/dev/null && { echo pass; return; }
  (( rc == 0 )) && echo pass || echo fail
}

generate_dashboard() {
  bash "$HARNESS_DIR/presentation/html/dashboard.sh" >/dev/null 2>&1 || true
}

_emit_health_change() {
  local h="$1"
  [[ "$h" == "$LAST_HEALTH" ]] && return 0
  LAST_HEALTH="$h"
  events_emit "runtime.health.$h"
}

_update_health() {
  local h=green
  (( FAILURES > 0 || STERILE > 0 || $(count_parked) > 0 )) && h=yellow
  (( FAILURES >= MAX_FAILURES || STERILE >= MAX_STERILE )) && h=red
  state_set health "$h" consecutive_failures "$FAILURES" consecutive_sterile "$STERILE"
  _emit_health_change "$h"
}

# ---- review + distill, inline after a successful build --------------------
_review_and_distill() {
  local task="$1" rlog rrc rres
  context_build review >/dev/null
  git_snapshot
  rlog="$LOGS_DIR/cycle-$(printf '%04d' "$CYCLE")-review-$(date +%s).log"
  events_emit review.started --loop review --task "$task"
  agents_run review "$WORKING_CONTEXT" "$rlog"; rrc=$?
  rres="$(classify_result review "$rlog" "$rrc")"

  if [[ "$rres" == pass ]] && validate_contract review; then
    mark_first_task_done
    commit_cycle review "$task"
    memory_log review pass "$rlog"
    state_set last_review pass
    events_emit review.passed --loop review --task "$task"
    _distill "$task"
  else
    [[ "$rres" == pass ]] || true
    validate_contract review || rollback_cycle
    memory_log_incident review "review failed for $task"
    state_set last_review fail
    events_emit review.failed --loop review --task "$task"
    (( FAILURES++ ))
  fi
}

_distill() {
  local task="$1" dlog before_skills after_skills before_mcp after_mcp
  context_build distill >/dev/null
  git_snapshot
  before_skills=$(find "$HARNESS_DIR/skills" -name SKILL.md 2>/dev/null | wc -l)
  before_mcp=$(find "$HARNESS_DIR/mcp" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
  dlog="$LOGS_DIR/cycle-$(printf '%04d' "$CYCLE")-distill-$(date +%s).log"
  events_emit distill.started --loop distill --task "$task"
  agents_run distill "$WORKING_CONTEXT" "$dlog" || true

  if validate_contract distill; then
    commit_cycle distill "$task"
    memory_log distill pass "$dlog"
    after_skills=$(find "$HARNESS_DIR/skills" -name SKILL.md 2>/dev/null | wc -l)
    after_mcp=$(find "$HARNESS_DIR/mcp" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    (( after_skills > before_skills )) && events_emit distill.skill_created --loop distill --task "$task"
    (( after_mcp > before_mcp )) && events_emit distill.mcp_created --loop distill --task "$task"
  else
    rollback_cycle
    memory_log_incident distill "out-of-scope write"
  fi
}

# ---- escalation: the doctrine's answer to a stall (never halt for a decision) --
# A stuck phase is routed to a decision instead of killing the runtime:
#   build  -> mark its task [!] so `plan` re-decides it (smaller slice / reinterpret / reject)
#   plan   -> drop the escalated task it cannot resolve, or auto-reject an un-plannable roadmap item
#   groom  -> drop a malformed inbox dump it keeps looping on
# The failed attempt is rolled back, the state change committed, breakers reset,
# and the loop lives on. die() is reserved for genuine infrastructure failure.
escalate() {
  local loop="$1" task
  task="$(current_task)"
  rollback_cycle
  memory_log_incident "$loop" "escalated after repeated failure/sterility (routed to a decision, not halted)"
  case "$loop" in
    build)
      mark_first_task_escalated
      events_emit decision.escalated --loop build --task "$task" --data "$(jq -cn --arg t "$task" '{task:$t,to:"plan"}' 2>/dev/null || echo '{}')"
      ;;
    plan)
      if (( $(count_sprint_escalated) > 0 )); then
        drop_first_escalated_task
      else
        reject_first_roadmap_pending
      fi
      events_emit decision.auto_rejected --loop plan
      ;;
    groom)
      drop_first_inbox_item
      events_emit decision.auto_rejected --loop groom
      ;;
    *)
      events_emit decision.escalated --loop "$loop"
      ;;
  esac
  commit_cycle "$loop" "escalation"
  FAILURES=0
  STERILE=0
  log "escalated $loop — the loop continues (no halt)"
}

# ---- one cycle ------------------------------------------------------------
run_cycle() {
  local loop; loop="$(next_loop)"

  if [[ "$loop" == idle ]]; then
    # Daemon mode: if tasks are parked on external resources, periodically run a
    # groom recheck so a resource that returned is noticed WITHOUT needing new
    # intake (fixes the "parked recheck only on inbox activity" starvation).
    if [[ "$HARNESS_DAEMON" == "1" ]] && (( $(count_parked) > 0 )); then
      (( IDLE_TICKS++ ))
      if (( IDLE_TICKS % PARKED_RECHECK == 0 )); then
        loop=groom
        log "daemon idle: rechecking $(count_parked) parked item(s) via groom"
      else
        state_set active_loop idle message "idle - $(count_parked) parked, waiting on resources"
        _update_health; events_emit cycle.idle; generate_dashboard
        return 11
      fi
    else
      state_set active_loop idle message "idle - no work"
      _update_health; events_emit cycle.idle
      if [[ "$HARNESS_DAEMON" == "1" ]]; then generate_dashboard; return 11; fi
      return 10   # done
    fi
  fi

  (( CYCLE++ ))
  local task; task="$(current_task)"
  state_set cycle "$CYCLE" active_loop "$loop" current_task "$task" message ""
  events_emit cycle.started --loop "$loop"
  events_emit "${loop}.started" --loop "$loop" --task "$task"
  log "cycle $CYCLE — $loop ${task:+($task)}"

  local fpb fpa start logfile rc dur_ms result changed
  fpb="$(fingerprint)"
  git_snapshot
  context_build "$loop" >/dev/null
  start="$(date +%s)"
  logfile="$LOGS_DIR/cycle-$(printf '%04d' "$CYCLE")-$loop-$start.log"
  agents_run "$loop" "$WORKING_CONTEXT" "$logfile"; rc=$?
  dur_ms=$(( ( $(date +%s) - start ) * 1000 ))
  fpa="$(fingerprint)"
  result="$(classify_result "$loop" "$logfile" "$rc")"
  [[ "$fpb" == "$fpa" ]] && changed=false || changed=true

  # contract check on apparent success
  if [[ "$result" == pass || "$result" == alldone || "$result" == blocked ]]; then
    validate_contract "$loop" || result="violation"
  fi

  case "$result" in
    pass|alldone|blocked)
      memory_log "$loop" pass "$logfile"
      # build cannot write SPRINT.md, so the RUNTIME marks its task's new state:
      [[ "$loop" == build && "$result" == blocked ]] && mark_first_task_parked
      # after grooming, un-park any task whose external resource returned
      [[ "$loop" == groom && "$result" == pass ]] && reconcile_sprint_parked
      commit_cycle "$loop" "$task"
      events_emit "${loop}.finished" --loop "$loop" --task "$task" --result pass --duration_ms "$dur_ms"
      FAILURES=0
      if [[ "$changed" == false && "$result" == pass ]]; then (( STERILE++ )); else STERILE=0; fi
      [[ "$loop" == build && "$result" == pass ]] && _review_and_distill "$task"
      ;;
    violation)
      rollback_cycle
      memory_log_incident "$loop" "out-of-scope write"
      events_emit "${loop}.failed" --loop "$loop" --task "$task" --result fail --duration_ms "$dur_ms"
      (( FAILURES++ ))
      ;;
    *)
      memory_log_incident "$loop" "$result"
      events_emit "${loop}.failed" --loop "$loop" --task "$task" --result fail --duration_ms "$dur_ms"
      (( FAILURES++ ))
      ;;
  esac

  log "cycle $CYCLE — result=$result changed=$changed failures=$FAILURES sterile=$STERILE"

  # A repeated failure or sterility is a DECISION POINT, not a reason to halt.
  # Instead of dying (which would be a disguised human-block), escalate: route
  # the stuck item to a fresh decision and keep the rest of the backlog flowing.
  if (( STERILE >= MAX_STERILE || FAILURES >= MAX_FAILURES )); then
    escalate "$loop"
  fi

  _update_health
  generate_dashboard
  return 0
}

on_int() {
  log "interrupted — killing agent session"
  [[ -n "${AGENT_PID:-}" ]] && { kill -TERM -"$AGENT_PID" 2>/dev/null || kill -TERM "$AGENT_PID" 2>/dev/null || true; }
  state_set health yellow message "interrupted"
  exit 130
}
on_exit() { generate_dashboard; }

main() {
  trap on_int INT TERM
  trap on_exit EXIT
  state_set pid "$$"
  CYCLE="$(state_get cycle)"; [[ "$CYCLE" =~ ^[0-9]+$ ]] || CYCLE=0
  log "Main loop starting (pid $$, max $MAX_ITERATIONS cycles, daemon=$HARNESS_DAEMON)"

  local i=0
  while (( i < MAX_ITERATIONS )); do
    run_cycle; rc=$?
    case "$rc" in
      10)
        state_set active_loop idle health green message "all work complete"
        _emit_health_change green
        events_emit cycle.finished
        generate_dashboard
        log "DONE — no work remains"
        exit 0
        ;;
      11) sleep "$(( $(interval) * 2 ))" ;;   # idle daemon: wait, do not count
      *)  (( i++ )); sleep "$(interval)" ;;
    esac
  done
  die "reached MAX_ITERATIONS=$MAX_ITERATIONS"
}

main "$@"
