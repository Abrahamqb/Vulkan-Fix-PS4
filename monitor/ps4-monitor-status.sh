#!/bin/bash
# ============================================================================
#  ps4-monitor-status.sh — show whether the monitor is running
#
#  Usage: ./monitor/ps4-monitor-status.sh
# ============================================================================
set -u
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SELF_DIR/.." && pwd)
LOG_DIR="${PS4_MONITOR_LOG_DIR:-$ROOT/logs}"
RUN_DIR="${PS4_MONITOR_RUN_DIR:-$ROOT/run}"
ERROR_FILE="${PS4_MONITOR_ERROR_FILE:-$ROOT/ps4-monitor-error.log}"

PID=$(cat "$RUN_DIR/main.pid" 2>/dev/null || cat "$RUN_DIR/monitor.pid" 2>/dev/null || true)
if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
  echo "ps4-monitor: running (pid $PID)"
else
  echo "ps4-monitor: not running"
fi

SESSION=$(cat "$RUN_DIR/current" 2>/dev/null || true)
[ -n "${SESSION:-}" ] && echo "Session log: $SESSION"
[ -f "$ERROR_FILE" ] && echo "Latest error report: $ERROR_FILE"

if [ -n "${SESSION:-}" ] && [ -f "$SESSION" ]; then
  echo
  echo "--- last 8 lines ---"
  tail -8 "$SESSION"
fi
