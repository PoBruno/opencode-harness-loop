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

# Concurrently-editable scope. A human may run interactive `opencode --agent desk`
# at any time; it runs OUTSIDE the git mutex and writes only the inbox. So a change
# under this path during another agent's cycle is far more likely a concurrent human
# edit than a write by the running agent. For any agent that does NOT own the inbox,
# the runtime therefore (a) does not attribute an inbox change to it in the contract
# check and (b) does not revert the inbox on that agent's rollback — so a mid-cycle
# desk edit is never blamed on, nor erased by, an unrelated failing cycle. The two
# inbox owners (desk, groom) are excluded: their rollback still reverts the inbox.
INTERACTIVE_SCOPE_RE='^\.harness/inbox/'
_owns_interactive_scope() { case "$1" in desk|groom) return 0 ;; *) return 1 ;; esac; }
# True when $2 is a concurrent interactive path that loop $1 does NOT own.
_foreign_interactive() {
  local loop="$1" f="$2"
  [[ -z "$loop" ]] && return 1
  _owns_interactive_scope "$loop" && return 1
  [[ "$f" =~ $INTERACTIVE_SCOPE_RE ]]
}

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
# runtime-owned output that the engine writes itself. With an optional <loop>, a
# concurrent interactive edit the loop does not own (see INTERACTIVE_SCOPE_RE) is
# also dropped, so it is never mis-attributed to the running agent.
git_changed_since_snapshot() {
  local loop="${1:-}"
  git_available || return 0
  local pre; pre="$(cat "$SNAPSHOT_FILE" 2>/dev/null || echo "")"
  local f
  {
    if [[ -n "$pre" ]]; then
      _git diff --name-only "$pre" 2>/dev/null || true
    else
      _git diff --name-only HEAD 2>/dev/null || true
    fi
    _git ls-files --others --exclude-standard 2>/dev/null || true
  } | sort -u | grep -vE "$HARNESS_RUNTIME_RE" | while IFS= read -r f; do
    _foreign_interactive "$loop" "$f" && continue
    printf '%s\n' "$f"
  done
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

# Remove exactly the untracked files that appeared since the snapshot (an
# out-of-scope file a rejected agent created), skipping runtime-owned output and
# any path matching $1 (a preserve regex, empty to preserve nothing). Untracked
# files that already existed at snapshot time are left alone.
_rollback_remove_untracked() {
  local preserve_re="$1" f
  [[ -f "$UNTRACKED_SNAPSHOT" ]] || return 0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ -n "$preserve_re" && "$f" =~ $preserve_re ]] && continue
    rm -f "$PROJECT_DIR/$f" 2>/dev/null || true
  done < <(comm -13 <(sort "$UNTRACKED_SNAPSHOT") \
                    <(_git ls-files --others --exclude-standard 2>/dev/null | sort) \
           | grep -vE "$HARNESS_RUNTIME_RE")
}

# Roll a failed cycle back to the pre-cycle snapshot. SCOPE-AWARE: for a failing
# agent that does not own the inbox, changes under the interactive scope (a likely
# concurrent human `desk` edit) are PRESERVED — the tracked ones are not reverted
# and the untracked ones are not removed — so an unrelated failing cycle can never
# erase a mid-cycle human edit. If the agent unexpectedly moved HEAD (agents do not
# commit; the runtime only commits on success), we fall back to a full hard reset,
# preserving nothing, since a path-scoped revert across a moved HEAD is unsafe.
git_rollback() {
  local loop="${1:-}"
  git_available || return 0
  local pre head; pre="$(cat "$SNAPSHOT_FILE" 2>/dev/null || echo "")"
  head="$(_git rev-parse HEAD 2>/dev/null || echo "")"

  local preserve_re=""
  if [[ -n "$loop" ]] && ! _owns_interactive_scope "$loop" \
     && { [[ -z "$pre" ]] || [[ -z "$head" ]] || [[ "$pre" == "$head" ]]; }; then
    preserve_re="$INTERACTIVE_SCOPE_RE"
  fi

  if [[ -z "$preserve_re" ]]; then
    # Full rollback: revert the entire tree (and any agent commit) to the snapshot.
    [[ -n "$pre" ]] && _git reset -q --hard "$pre" 2>/dev/null || true
    _rollback_remove_untracked ""
    return 0
  fi

  # Scope-aware rollback (HEAD unchanged): restore every tracked file changed since
  # the snapshot EXCEPT the preserved interactive scope, then remove the untracked
  # delta EXCEPT that scope.
  if [[ -n "$pre" ]]; then
    local f
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      [[ "$f" =~ $preserve_re ]] && continue
      _git checkout -q "$pre" -- "$f" 2>/dev/null || true
    done < <(_git diff --name-only "$pre" 2>/dev/null | grep -vE "$HARNESS_RUNTIME_RE")
  fi
  _rollback_remove_untracked "$preserve_re"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    snapshot) git_snapshot ;;
    changed)  git_changed_since_snapshot "$@" ;;
    commit)   git_commit "$@" ;;
    rollback) git_rollback "$@" ;;
    *) echo "usage: git.sh {snapshot|changed [loop]|commit <msg> [paths...]|rollback [loop]}" >&2; exit 2 ;;
  esac
fi
