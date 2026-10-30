#!/bin/bash
# ============================================================================
#  ps4-monitor-stop.sh — stop the background PS4 monitor
#
#  Usage: ./monitor/ps4-monitor-stop.sh
# ============================================================================
set -u
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SELF_DIR/.." && pwd)
LOG_DIR="${PS4_MONITOR_LOG_DIR:-$ROOT/logs}"
RUN_DIR="${PS4_MONITOR_RUN_DIR:-$ROOT/run}"

PID=""
for p in "$RUN_DIR/main.pid" "$RUN_DIR/monitor.pid"; do
  [ -f "$p" ] && { PID=$(cat "$p" 2>/dev/null || true); [ -n "$PID" ] && break; }
done

if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
  echo "ps4-monitor: not running"
  rm -f "$RUN_DIR/main.pid" "$RUN_DIR/monitor.pid" "$RUN_DIR/dmesg.pid" "$RUN_DIR/sample.pid" "$RUN_DIR/video.pid"
  exit 0
fi

touch "$RUN_DIR/stop" 2>/dev/null || true
kill "$PID" 2>/dev/null || true
for _ in 1 2 3 4 5; do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
kill -9 "$PID" 2>/dev/null || true

pkill -f 'dmesg --since now --time-format iso -w' 2>/dev/null || true
pkill -f 'dmesg --time-format iso -w' 2>/dev/null || true

LOG=$(cat "$RUN_DIR/current" 2>/dev/null || true)
if [ -n "${LOG:-}" ] && [ -f "$LOG" ]; then
  {
    echo "=== ps4-monitor stopped $(date -Is) ==="
    echo "--- last relevant lines ---"
    grep -iE 'amdgpu|drm|ring|reset|timeout|link|HDMI|connector|temp=|ERROR' "$LOG" | tail -40
  } >> "$LOG" 2>/dev/null || true
  cp -f /var/log/Xorg.0.log "$LOG_DIR/Xorg.0.log.copy" 2>/dev/null || true
  echo "Log saved to: $LOG"
fi

rm -f "$RUN_DIR/main.pid" "$RUN_DIR/monitor.pid" "$RUN_DIR/dmesg.pid" "$RUN_DIR/sample.pid" "$RUN_DIR/video.pid" "$RUN_DIR/stop"
