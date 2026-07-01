#!/usr/bin/env bash
# loop.sh — friendly entrypoint. Boots the runtime (scheduler + Main Loop).
#
#   bash .harness/loop.sh            # run until idle (or a breaker trips)
#   bash .harness/loop.sh --once     # a single cycle
#   bash .harness/loop.sh --daemon   # keep waiting for new inbox items
#   bash .harness/loop.sh --help
exec "$(cd "$(dirname "$0")" && pwd)/runtime/scheduler.sh" --bootstrap "$@"
