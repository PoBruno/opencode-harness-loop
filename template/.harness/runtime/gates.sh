#!/usr/bin/env bash
# gates.sh — the validation wheel used by the Review Engine (backpressure).
#
# Runs cheapest -> most expensive so failures surface fast: type-check -> lint
# -> test -> build. ANY non-zero gate rejects the iteration. Specialize per
# project either via .harness/gates.local.sh (exporting GATE_TYPECHECK,
# GATE_LINT, GATE_TEST, GATE_BUILD) or via auto-detection from the manifest.

set -uo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
cd "$PROJECT_DIR"

GATE_TYPECHECK="" GATE_LINT="" GATE_TEST="" GATE_BUILD=""

_load_or_detect() {
  if [[ -f "$HARNESS_DIR/gates.local.sh" ]]; then
    # shellcheck source=/dev/null
    source "$HARNESS_DIR/gates.local.sh"; return
  fi
  if [[ -f package.json ]]; then
    local pm="npm"
    [[ -f pnpm-lock.yaml ]] && pm="pnpm"; [[ -f yarn.lock ]] && pm="yarn"; [[ -f bun.lockb ]] && pm="bun"
    _has() { command -v jq >/dev/null 2>&1 && jq -e --arg s "$1" '.scripts[$s] // empty' package.json >/dev/null 2>&1; }
    if _has typecheck; then GATE_TYPECHECK="$pm run typecheck"; elif [[ -f tsconfig.json ]]; then GATE_TYPECHECK="npx --no-install tsc --noEmit"; fi
    _has lint  && GATE_LINT="$pm run lint"
    _has test  && GATE_TEST="$pm test"
    _has build && GATE_BUILD="$pm run build"
  elif [[ -f pyproject.toml || -f requirements.txt || -f setup.py ]]; then
    command -v ruff   >/dev/null 2>&1 && GATE_LINT="ruff check ."
    command -v mypy   >/dev/null 2>&1 && GATE_TYPECHECK="mypy ."
    command -v pytest >/dev/null 2>&1 && GATE_TEST="pytest -q"
  elif [[ -f Cargo.toml ]]; then
    GATE_TYPECHECK="cargo check"; GATE_LINT="cargo clippy -- -D warnings"; GATE_TEST="cargo test"; GATE_BUILD="cargo build"
  elif [[ -f go.mod ]]; then
    GATE_TYPECHECK="go vet ./..."; GATE_TEST="go test ./..."; GATE_BUILD="go build ./..."
  fi
}

_run() {
  local name="$1" cmd="$2"
  [[ -z "$cmd" ]] && return 0
  printf '  gate: %-10s %s\n' "$name" "$cmd" >&2
  eval "$cmd" || { printf 'GATE FAILED: %s\n' "$name" >&2; return 1; }
}

main() {
  _load_or_detect
  if [[ "${1:-}" == "--list" ]]; then
    printf 'typecheck: %s\nlint:      %s\ntest:      %s\nbuild:     %s\n' \
      "${GATE_TYPECHECK:-<none>}" "${GATE_LINT:-<none>}" "${GATE_TEST:-<none>}" "${GATE_BUILD:-<none>}"
    return 0
  fi
  if [[ -z "$GATE_TYPECHECK$GATE_LINT$GATE_TEST$GATE_BUILD" ]]; then
    echo "gates: none configured or detected" >&2; return 0
  fi
  _run typecheck "$GATE_TYPECHECK" || return 1
  _run lint      "$GATE_LINT"      || return 1
  _run test      "$GATE_TEST"      || return 1
  _run build     "$GATE_BUILD"     || return 1
  echo "gates: all passed" >&2
}

main "$@"
