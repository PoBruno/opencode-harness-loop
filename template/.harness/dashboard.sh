#!/usr/bin/env bash
# dashboard.sh — friendly entrypoint. Regenerates the static HTML dashboard
# from state/ + events/ (no server needed; open the file directly).
#
#   bash .harness/dashboard.sh
exec "$(cd "$(dirname "$0")" && pwd)/presentation/html/dashboard.sh" "$@"
