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
LAST_FAIL_LOG=""

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  log "FATAL: $*"
  git_unlock 2>/dev/null || true   # explicit release (do not rely on OS fd-close)
  state_set health red message "$*"
  _emit_health_change red
  generate_dashboard
  exit 1
}

fingerprint() {
  {
    git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo "no-head"
    git -C "$PROJECT_DIR" diff HEAD -- . \
      ':(exclude).harness/state' ':(exclude).harness/events' ':(exclude).harness/logs' \
      ':(exclude).harness/memory/history' ':(exclude).harness/presentation/html' 2>/dev/null || true
    git -C "$PROJECT_DIR" ls-files --others --exclude-standard -z 2>/dev/null \
      | while IFS= read -r -d '' f; do
          case "$f" in
            .harness/state/*|.harness/events/*|.harness/logs/*|.harness/memory/history/*|.harness/presentation/html/*) continue ;;
          esac
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

# Distinguish a broken environment/gate (NOT a decision — re-planning a correct
# task cannot fix a missing dependency or a malformed gate command) from a real
# implementation failure. Scans a log for infrastructure signatures.
_looks_like_infra() {
  local logfile="${1:-}"
  [[ -f "$logfile" ]] || return 1
  grep -qiE 'command not found|: not found|no such file or directory|modulenotfounderror|importerror: no module|not recognized as|executable file not found|cannot execute|permission denied|no such module|unable to locate|is not installed' \
    "$logfile" 2>/dev/null
}

generate_dashboard() {
  bash "$HARNESS_DIR/presentation/html/dashboard.sh" >/dev/null 2>&1 || true
}

# Acquire the git mutex for a cycle. The Main Loop holds it for the whole cycle
# (checkpoint -> snapshot -> agent -> validate -> commit/rollback), because the
# snapshot-based contract check and rollback require exclusive access from
# snapshot to commit. It therefore NEVER proceeds unlocked (that would reopen the
# very race the mutex prevents). Instead it waits — the only holder is the
# watcher, whose hold is bounded by INTAKE_TIMEOUT — retrying with a short per-
# attempt wait and publishing runtime.lock_contended (visible in the Decision Log)
# so the wait is observable. Only if the watcher exceeds even its own timeout (a
# genuine deadlock, not normal contention) does it halt honestly via die().
_acquire_git_lock() {
  local phase="$1" i max
  max="${MAIN_LOCK_RETRIES:-24}"   # * MAIN_LOCK_WAIT(15s) ~= 6min, covers the watcher's INTAKE_TIMEOUT bound
  for (( i = 1; i <= max; i++ )); do
    GIT_LOCK_WAIT="${MAIN_LOCK_WAIT:-15}" git_lock && return 0
    if (( i == 1 || i % 4 == 0 )); then
      events_emit runtime.lock_contended --loop "$phase" --data "$(jq -cn --argjson s "$(( i * ${MAIN_LOCK_WAIT:-15} ))" '{waited_s:$s}' 2>/dev/null || echo '{}')"
      log "WARN: git mutex held by the intake watcher ($(( i * ${MAIN_LOCK_WAIT:-15} ))s waited)"
    fi
  done
  events_emit runtime.lock_contended --loop "$phase" --result deadlock
  die "git mutex deadlock: the intake watcher held the lock beyond its own timeout (~$(( max * ${MAIN_LOCK_WAIT:-15} ))s). A desk run is likely stuck — check .harness/logs/intake-*.log, then re-run."
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
    # Review verdict is retry. Its memory consolidation (learnings about what was
    # wrong) is valuable and IN SCOPE, so COMMIT it — leaving it uncommitted would
    # leak into the next build's contract check as a false out-of-scope write.
    # Only roll back if review itself wrote out of scope.
    if validate_contract review; then
      commit_cycle review "$task"
    else
      rollback_cycle
    fi
    LAST_FAIL_LOG="$rlog"
    memory_log_incident review "review verdict: retry for $task"
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
#   build   -> mark its task [!] so `planner` re-decides it (smaller slice / reinterpret / reject)
#   planner -> drop the escalated task it cannot resolve, or auto-reject an un-plannable roadmap item
#   groom   -> drop a malformed inbox dump it keeps looping on
# Note on attribution: `review` runs INLINE inside a build cycle, so a run of
# review rejections increments the same global FAILURES and escalates with
# $loop == "build" (the outer run_cycle phase). A `decision.escalated --loop build`
# can therefore mean "review kept rejecting this build" — routing the task back to
# the planner is still the right response (the planner re-slices the bad task).
#
# EXCEPTION: a broken gate/environment is NOT a decision. Re-planning a correct
# task cannot fix a missing dependency or a malformed gate command, and would just
# loop auto-rejecting correct tasks. So an infra-flavored failure halts honestly
# (die) for a human to fix, instead of escalating to the planner.
escalate() {
  local loop="$1" task
  task="$(current_task)"

  if (( FAILURES >= MAX_FAILURES )) && _looks_like_infra "$LAST_FAIL_LOG"; then
    die "infrastructure/gate failure (not a task decision) after $FAILURES attempts — the gates or environment look broken (missing dependency or a malformed command in .harness/gates.local.sh). Fix it and re-run. Log: $LAST_FAIL_LOG"
  fi

  rollback_cycle
  memory_log_incident "$loop" "escalated after repeated failure/sterility (routed to a decision, not halted)"
  case "$loop" in
    build)
      mark_first_task_escalated
      events_emit decision.escalated --loop build --task "$task" --data "$(jq -cn --arg t "$task" '{task:$t,to:"planner"}' 2>/dev/null || echo '{}')"
      ;;
    planner)
      if (( $(count_sprint_escalated) > 0 )); then
        drop_first_escalated_task
      else
        reject_first_roadmap_pending
      fi
      events_emit decision.auto_rejected --loop planner
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
  _acquire_git_lock "$loop"
  # Checkpoint any pending desk write (interactive `opencode --agent desk` OR the
  # watcher) BEFORE snapshotting, so this cycle's rollback can never silently erase
  # an uncommitted intake item. SCOPED to the inbox and PARKED only: any other dirty
  # file is deliberately left out so it surfaces as a normal contract violation next,
  # instead of being silently swallowed under a "pending intake" checkpoint.
  git_commit "harness: checkpoint pending intake" .harness/inbox .harness/PARKED.md
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
      LAST_FAIL_LOG="$logfile"
      memory_log_incident "$loop" "out-of-scope write"
      events_emit "${loop}.failed" --loop "$loop" --task "$task" --result fail --duration_ms "$dur_ms"
      (( FAILURES++ ))
      ;;
    *)
      # A failed attempt: discard its uncommitted partial work so nothing leaks
      # into the next cycle's contract check (every cycle ends committed or clean).
      rollback_cycle
      LAST_FAIL_LOG="$logfile"
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
  git_unlock
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

  # Reached the iteration ceiling — a clean, expected stop (this is exactly how
  # --once ends after its single cycle), NOT an error. Health is green if the
  # backlog is empty, yellow if work remains (just run again to continue).
  local remaining h="green" msg="reached the iteration ceiling ($MAX_ITERATIONS cycles)"
  remaining=$(( $(count_inbox_pending) + $(count_sprint_open) + $(count_sprint_escalated) + $(count_roadmap_pending) ))
  if (( remaining > 0 )); then
    h="yellow"; msg="$msg — $remaining work item(s) still pending; run again to continue"
  fi
  state_set active_loop idle health "$h" message "$msg"
  _emit_health_change "$h"
  events_emit cycle.finished
  generate_dashboard
  log "$msg"
  exit 0
}

# Only run the loop when executed directly; sourcing exposes the functions for
# testing (e.g. _acquire_git_lock, classify_result, _looks_like_infra) without
# side effects.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
