#!/usr/bin/env bash
# git.sh — version-control helpers used by state.sh for commit / rollback.
#
# The loop is disposable; the state is sacred. Every validated cycle is
# committed; every failed cycle is rolled back to the pre-cycle snapshot so a
# bad agent run never leaves the tree in a half-broken state.

: "${HARNESS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
SNAPSHOT_FILE="$HARNESS_DIR/state/.pre_cycle_sha"
UNTRACKED_SNAPSHOT="$HARNESS_DIR/state/.pre_cycle_untracked"

_git() { git -C "$PROJECT_DIR" "$@"; }

# Runtime-OWNED paths: written by the engine itself (never by an agent), so they
# must be excluded from the agent contract check and never removed on rollback —
# otherwise a bookkeeping write (episodic history, the dashboard, the event bus)
# leaks into the NEXT cycle's diff and is mis-attributed to the agent as an
# out-of-scope write (a false-violation cascade that stalls the loop).
HARNESS_RUNTIME_RE='^\.harness/(state|events|logs|memory/history|presentation/html)/'

# Cross-process mutex. The Main Loop (cycle.sh) and the Half-Loop watcher
# (intake_loop.sh) both mutate git; without serialization a watcher commit landing
# mid-cycle would either be discarded by that cycle's rollback (silent loss of an
# intake item) or be mis-attributed to the running agent. git_lock is held for the
# whole git-critical section of each side; the low-frequency watcher simply waits
# for the current cycle. Degrades to no-op if flock is unavailable.
GIT_MUTEX="$HARNESS_DIR/state/.git.mutex"

git_lock() {
  command -v flock >/dev/null 2>&1 || return 0
  mkdir -p "$(dirname "$GIT_MUTEX")"
  exec 8>"$GIT_MUTEX" 2>/dev/null || return 0
  flock -w "${GIT_LOCK_WAIT:-900}" 8   # 0 if acquired, non-zero on timeout
}
git_unlock() {
  command -v flock >/dev/null 2>&1 || return 0
  flock -u 8 2>/dev/null || true
}

git_available() {
  command -v git >/dev/null 2>&1 && _git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Record HEAD AND the untracked-file set before an agent runs, so rollback can
# both revert tracked changes and remove any out-of-scope file the agent created.
git_snapshot() {
  git_available || return 0
  mkdir -p "$HARNESS_DIR/state"
  _git rev-parse HEAD >"$SNAPSHOT_FILE" 2>/dev/null || echo "" >"$SNAPSHOT_FILE"
  _git ls-files --others --exclude-standard >"$UNTRACKED_SNAPSHOT" 2>/dev/null || : >"$UNTRACKED_SNAPSHOT"
}

# Files changed since the snapshot (tracked diffs + untracked), excluding
# runtime-owned output that the engine writes itself.
git_changed_since_snapshot() {
  git_available || return 0
  local pre; pre="$(cat "$SNAPSHOT_FILE" 2>/dev/null || echo "")"
  {
    if [[ -n "$pre" ]]; then
      _git diff --name-only "$pre" 2>/dev/null || true
    else
      _git diff --name-only HEAD 2>/dev/null || true
    fi
    _git ls-files --others --exclude-standard 2>/dev/null || true
  } | sort -u | grep -vE "$HARNESS_RUNTIME_RE" || true
}

# Commit a set of path prefixes with a message. Ephemeral output (state, events,
# logs, the generated dashboard) is never staged; versioned memory/history IS.
git_commit() {
  local msg="$1"; shift
  git_available || return 0
  if (( $# > 0 )); then
    _git add -- "$@" 2>/dev/null || true
  else
    _git add -A 2>/dev/null || true
  fi
  _git reset -q -- "$HARNESS_DIR/state" "$HARNESS_DIR/events" "$HARNESS_DIR/logs" \
    "$HARNESS_DIR/presentation/html" 2>/dev/null || true
  if ! _git diff --cached --quiet 2>/dev/null; then
    _git commit -q -m "$msg" 2>/dev/null || true
  fi
}

# Roll the tree back to the pre-cycle snapshot: revert tracked changes AND any
# commit the agent made, then remove exactly the untracked files that appeared
# since the snapshot (an out-of-scope file a rejected agent created). Untracked
# files that already existed at snapshot time are left alone.
git_rollback() {
  git_available || return 0
  local pre; pre="$(cat "$SNAPSHOT_FILE" 2>/dev/null || echo "")"
  [[ -n "$pre" ]] && _git reset -q --hard "$pre" 2>/dev/null || true
  [[ -f "$UNTRACKED_SNAPSHOT" ]] || return 0
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] && rm -f "$PROJECT_DIR/$f" 2>/dev/null || true
  done < <(comm -13 <(sort "$UNTRACKED_SNAPSHOT") \
                    <(_git ls-files --others --exclude-standard 2>/dev/null | sort) \
           | grep -vE "$HARNESS_RUNTIME_RE")
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    snapshot) git_snapshot ;;
    changed)  git_changed_since_snapshot ;;
    commit)   git_commit "$@" ;;
    rollback) git_rollback ;;
    *) echo "usage: git.sh {snapshot|changed|commit <msg> [paths...]|rollback}" >&2; exit 2 ;;
  esac
fi
