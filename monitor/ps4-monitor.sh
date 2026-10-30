#!/bin/bash
# ============================================================================
#  ps4-monitor.sh — persistent PS4 GPU/video monitor
#
#  Runs in the background while you play or while install.sh checks Mesa.
#  It records kernel messages, temperature, fan, VRAM/GTT, RAM, Xorg and the
#  video connector. If it detects a GPU hang, a lost video link or an Xorg
#  crash, it writes a human-readable report that survives a reboot:
#
#      <repo>/ps4-monitor-error.log
#      <repo>/logs/ps4-monitor-error-<timestamp>.log
#
#  USAGE
#    ./monitor/ps4-monitor.sh              # start in the background
#    ./monitor/ps4-monitor.sh --foreground # stay in the terminal (debug)
#    ./monitor/ps4-monitor.sh --test-report# write a sample report and exit
#    ./monitor/ps4-monitor-stop.sh         # stop it
#    ./monitor/ps4-monitor-status.sh       # status and last lines
#
#  ENVIRONMENT (useful for tests)
#    PS4_MONITOR_LOG_DIR     session/report directory (default <repo>/logs)
#    PS4_MONITOR_RUN_DIR     PID/state directory      (default <repo>/run)
#    PS4_MONITOR_ERROR_FILE  latest report file        (default <repo>/ps4-monitor-error.log)
#    PS4_MONITOR_CONNECTOR   connector status file to watch
# ============================================================================
set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SELF_DIR/.." && pwd)
LOG_DIR="${PS4_MONITOR_LOG_DIR:-$ROOT/logs}"
RUN_DIR="${PS4_MONITOR_RUN_DIR:-$ROOT/run}"
ERROR_FILE="${PS4_MONITOR_ERROR_FILE:-$ROOT/ps4-monitor-error.log}"
mkdir -p "$LOG_DIR" "$RUN_DIR"

MODE="background"
case "${1:-}" in
  --foreground) MODE="foreground" ;;
  --test-report) MODE="test" ;;
  -h|--help)
    awk 'NR==1{next} /^# ============================================================================$/{if (++n==2) exit} {print}' "$0"
    exit 0 ;;
  "") : ;;
  *) echo "ps4-monitor: unknown option: $1 (use --help)" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Report writer. Kept before the startup checks so --test-report can use it.
# ---------------------------------------------------------------------------
write_report() {
  local kind="$1" detail="$2"
  local lock="$RUN_DIR/error.lock"
  local stamp file last now
  stamp=$(date +%Y%m%d-%H%M%S)
  file="$LOG_DIR/ps4-monitor-error-$stamp-$kind.log"

  # Throttle repeated reports of the same kind (dmesg can repeat lines).
  last="$RUN_DIR/last-error-$kind"
  now=$(date +%s)
  if [ -f "$last" ]; then
    local previous
    previous=$(cat "$last" 2>/dev/null || echo 0)
    [ -n "$previous" ] || previous=0
    case "$previous" in *[!0-9]*) previous=0 ;; esac
    if [ $((now - previous)) -lt 20 ]; then
      return 0
    fi
  fi
  echo "$now" > "$last" 2>/dev/null || true

  # Serialize reports from the dmesg, video and sample watchers.
  local have_lock=0
  if command -v flock >/dev/null 2>&1; then
    if exec 9>"$lock" 2>/dev/null; then
      if ! flock -n 9 2>/dev/null; then
        exec 9>&-
        return 0
      fi
      have_lock=1
    fi
  fi

  {
    echo "=============================================================="
    echo " PS4 MONITOR — ERROR REPORT"
    echo "=============================================================="
    echo "Generated: $(date -Is)"
    echo "Kind:      $kind"
    echo "Detected:  $detail"
    echo
    echo "If you are reading this after the screen went black or the"
    echo "PS4 stopped responding, the monitor caught this before/while"
    echo "the video was lost. The information below is preserved on disk."
    echo
    case "$kind" in
      gpu-hang)
        echo "WHAT IT MEANS"
        echo "  The amdgpu graphics ring stopped responding and the GPU"
        echo "  recovery failed. This is the known RADV bug from the system"
        echo "  Mesa 26.0.8 on the PS4 'Liverpool' GPU. The display can"
        echo "  freeze or go black and only a reboot usually recovers it."
        echo
        echo "WHAT TO DO"
        echo "  1. Reboot the PS4 (or write 1 to /sys/class/drm/card0/device/reset as root)."
        echo "  2. Launch games with Mesa 25.3.5:"
        echo "       $ROOT/vulkan-run.sh --mesa 25.3.5 -- %command%"
        echo "  3. For 32-bit games use: --wined3d --proton"
        echo "  4. Run $ROOT/check.sh to verify the stable Mesa copies."
        ;;
      display-lost)
        echo "WHAT IT MEANS"
        echo "  The video connector changed to 'disconnected' after having"
        echo "  been connected. The GPU or the display link probably hung."
        echo
        echo "WHAT TO DO"
        echo "  1. Reboot if the image does not come back."
        echo "  2. Check the HDMI/display cable and connector."
        echo "  3. Use Mesa 25.3.5 and run check.sh."
        ;;
      xorg-unresponsive)
        echo "WHAT IT MEANS"
        echo "  xrandr stopped answering, so the Xorg server is hung or the"
        echo "  GPU is no longer able to scan out an image."
        echo
        echo "WHAT TO DO"
        echo "  1. Reboot the PS4."
        echo "  2. Use Mesa 25.3.5 for games (vulkan-run.sh --mesa 25.3.5)."
        ;;
      xorg-crash)
        echo "WHAT IT MEANS"
        echo "  Xorg is no longer running. The desktop session may have"
        echo "  crashed, often as a consequence of a GPU reset."
        echo
        echo "WHAT TO DO"
        echo "  1. Reboot or restart the display manager."
        echo "  2. Use Mesa 25.3.5 for games and check the report below."
        ;;
      memory)
        echo "WHAT IT MEANS"
        echo "  The kernel reported an out-of-memory event. With 4.8 GiB"
        echo "  of RAM and no swap, Proton + DXVK can exhaust memory."
        echo
        echo "WHAT TO DO"
        echo "  1. Close other applications before playing."
        echo "  2. Consider enabling swap/zram."
        ;;
      video-link)
        echo "WHAT IT MEANS"
        echo "  The kernel reported a display-link/HDMI problem."
        echo
        echo "WHAT TO DO"
        echo "  1. Check the cable and connector."
        echo "  2. Reboot if there is no image."
        ;;
      *)
        echo "WHAT IT MEANS"
        echo "  The monitor recorded an event that may explain a crash or"
        echo "  a video loss. Review the kernel lines below."
        ;;
    esac
    echo
    echo "--- SYSTEM AT DETECTION --------------------------------------"
    echo "kernel:    $(uname -r)"
    echo "cmdline:   $(cat /proc/cmdline 2>/dev/null)"
    echo "uptime:    $(cat /proc/uptime 2>/dev/null)"
    if [ -r /etc/os-release ]; then
      # shellcheck disable=SC1091
      . /etc/os-release
      echo "distro:    ${PRETTY_NAME:-${NAME:-unknown}}"
    fi
    echo "Mesa env:  VULKAN_MESA_ACTIVE=${VULKAN_MESA_ACTIVE:-system}"
    echo "           VK_DRIVER_FILES=${VK_DRIVER_FILES:-<system default>}"
    echo "DISPLAY:   ${DISPLAY:-<unset>}  XAUTHORITY=${XAUTHORITY:-<unset>}"
    echo "connector: ${CONNECTOR:-<not found>} = $(cat "${CONNECTOR:-/dev/null}" 2>/dev/null || echo '?')"
    echo "temp:      $(cat /sys/devices/platform/ps4-fan/hwmon/hwmon0/temp1_input 2>/dev/null || echo '?') (millidegrees C)"
    echo "fan:       $(cat /sys/devices/platform/ps4-fan/hwmon/hwmon0/fan1_input 2>/dev/null || echo '?')"
    echo "vram used: $(cat /sys/class/drm/card0/device/mem_info_vram_used 2>/dev/null || echo '?')"
    echo "gtt used:  $(cat /sys/class/drm/card0/device/mem_info_gtt_used 2>/dev/null || echo '?')"
    echo "Xorg pids: $(pgrep -c Xorg 2>/dev/null || echo 0)"
    echo
    echo "--- LAST RELEVANT LINES FROM THE SESSION LOG -----------------"
    if [ -n "${SESSION:-}" ] && [ -f "$SESSION" ]; then
      grep -iE 'amdgpu|drm|ring|reset|timeout|link|HDMI|connector|temp=|ERROR|Xorg|Fatal|oom|killed' \
        "$SESSION" 2>/dev/null | tail -120
      echo
      echo "--- LAST 40 LINES OF THE SESSION LOG -------------------------"
      tail -40 "$SESSION" 2>/dev/null
      echo
      echo "Full session log: $SESSION"
    else
      echo "  (no session log available)"
    fi
    echo
    echo "Report written by ps4-monitor.sh at $(date -Is)."
    echo "=============================================================="
  } > "$file" 2>&1

  cp -f "$file" "$ERROR_FILE" 2>/dev/null || true
  sync 2>/dev/null || true
  printf 'ps4-monitor: ERROR REPORT -> %s\n' "$ERROR_FILE" >&2
  printf 'ps4-monitor: full report  -> %s\n' "$file" >&2
  [ "$have_lock" = 1 ] && exec 9>&-
}

if [ "$MODE" = "test" ]; then
  CONNECTOR="${PS4_MONITOR_CONNECTOR:-}"
  SESSION="$LOG_DIR/session-test-$(date +%Y%m%d-%H%M%S).log"
  printf '=== ps4-monitor test session %s ===\n' "$(date -Is)" > "$SESSION"
  printf 'amdgpu: ring gfx timeout, signaled seq=1, emitted seq=2\n' >> "$SESSION"
  write_report "test" "Synthetic test line: amdgpu: ring gfx timeout, signaled seq=1, emitted seq=2"
  echo "Test report written to: $ERROR_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Avoid duplicate monitors (check before detaching).
# ---------------------------------------------------------------------------
if [ -f "$RUN_DIR/monitor.pid" ]; then
  oldpid=$(cat "$RUN_DIR/monitor.pid" 2>/dev/null || true)
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    echo "ps4-monitor: already running (pid $oldpid)"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Detach before creating any watcher, so the background child owns them all.
# ---------------------------------------------------------------------------
if [ "$MODE" = "background" ] && [ "${PS4_MONITOR_DAEMONIZED:-0}" != 1 ]; then
  PS4_MONITOR_DAEMONIZED=1 setsid nohup "$0" --foreground >/dev/null 2>&1 < /dev/null &
  echo "ps4-monitor: started in the background. Logs: $LOG_DIR"
  exit 0
fi

# ---------------------------------------------------------------------------
# Find the video connector.
# ---------------------------------------------------------------------------
CONNECTOR="${PS4_MONITOR_CONNECTOR:-}"
if [ -z "$CONNECTOR" ]; then
  for f in /sys/class/drm/card0-HDMI-A-1/status /sys/class/drm/card*-*/status; do
    [ -f "$f" ] && { CONNECTOR="$f"; break; }
  done
fi

TS=$(date +%Y%m%d-%H%M%S)
SESSION="$LOG_DIR/session-$TS.log"
printf '%s\n' "$SESSION" > "$RUN_DIR/current"
rm -f "$RUN_DIR/stop"

{
  echo "=== ps4-monitor started $(date -Is) ==="
  echo "kernel: $(uname -r)"
  echo "distro: $(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"')"
  echo "cmdline: $(cat /proc/cmdline 2>/dev/null)"
  echo "uptime: $(cat /proc/uptime 2>/dev/null)"
  echo "Mesa env: VULKAN_MESA_ACTIVE=${VULKAN_MESA_ACTIVE:-system}"
  echo "connector: ${CONNECTOR:-<not found>}"
  echo
} >> "$SESSION"

# ---------------------------------------------------------------------------
# 1) Kernel messages, line by line.
# ---------------------------------------------------------------------------
DMESG_PID=""
if command -v dmesg >/dev/null 2>&1; then
  if dmesg --since now --time-format iso >/dev/null 2>&1; then
    (
      stdbuf -oL dmesg --since now --time-format iso -w 2>&1 | while IFS= read -r line; do
        printf '%s\n' "$line" >> "$SESSION"
        case "$line" in
          *"ring gfx timeout"*|*"GPU Recovery Failed"*|*"ring gfx test failed"*|*"GPU reset"*|*"resume of IP block"*)
            write_report "gpu-hang" "$line" ;;
          *"link training failed"*|*"no EDID"*|*"HDMI"*"disconnect"*|*"drm"*"disconnected"*)
            write_report "video-link" "$line" ;;
          *"Fatal server error"*|*"(EE) Server terminated"*|*"(EE) "*)
            write_report "xorg-crash" "$line" ;;
          *"Out of memory"*|*"oom-kill"*|*"Killed process"*)
            write_report "memory" "$line" ;;
        esac
      done
    ) &
    DMESG_PID=$!
  else
    (
      stdbuf -oL dmesg --time-format iso -w 2>&1 | while IFS= read -r line; do
        printf '%s\n' "$line" >> "$SESSION"
        case "$line" in
          *"ring gfx timeout"*|*"GPU Recovery Failed"*|*"ring gfx test failed"*|*"GPU reset"*|*"resume of IP block"*)
            write_report "gpu-hang" "$line" ;;
          *"Fatal server error"*|*"(EE) Server terminated"*)
            write_report "xorg-crash" "$line" ;;
          *"Out of memory"*|*"oom-kill"*|*"Killed process"*)
            write_report "memory" "$line" ;;
        esac
      done
    ) &
    DMESG_PID=$!
  fi
  echo "$DMESG_PID" > "$RUN_DIR/dmesg.pid"
fi

# ---------------------------------------------------------------------------
# 2) State sampling every second.
# ---------------------------------------------------------------------------
(
  n=0
  while :; do
    [ -f "$RUN_DIR/stop" ] && break
    T=$(cat /sys/devices/platform/ps4-fan/hwmon/hwmon0/temp1_input 2>/dev/null)
    F=$(cat /sys/devices/platform/ps4-fan/hwmon/hwmon0/fan1_input 2>/dev/null)
    VU=$(cat /sys/class/drm/card0/device/mem_info_vram_used 2>/dev/null)
    GU=$(cat /sys/class/drm/card0/device/mem_info_gtt_used 2>/dev/null)
    MA=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)
    X=$(pgrep -c Xorg 2>/dev/null || true)
    W=$(pgrep -c -f 'vkcube|proton|wine' 2>/dev/null || true)
    printf '[%s] temp=%s fan=%s vram_used=%s gtt_used=%s memavail_kb=%s xorg=%s apps=%s\n' \
      "$(date +%H:%M:%S)" "${T:-?}" "${F:-?}" "${VU:-?}" "${GU:-?}" "${MA:-?}" "${X:-?}" "${W:-?}" >> "$SESSION"
    n=$((n + 1))
    [ $((n % 5)) -eq 0 ] && sync 2>/dev/null || true
    sleep 1
  done
) &
SAMPLE_PID=$!
echo "$SAMPLE_PID" > "$RUN_DIR/sample.pid"
echo "$$" > "$RUN_DIR/main.pid"
echo "$$" > "$RUN_DIR/monitor.pid"

# ---------------------------------------------------------------------------
# 3) Video link/Xorg state every 5 seconds.
# ---------------------------------------------------------------------------
(
  had_video=0
  xr_ok=0
  xorg_seen=0
  disc=0
  [ -n "$CONNECTOR" ] && [ "$(cat "$CONNECTOR" 2>/dev/null)" = "connected" ] && had_video=1
  while :; do
    [ -f "$RUN_DIR/stop" ] && break
    S=$(cat "$CONNECTOR" 2>/dev/null)
    XR=$(timeout 3 xrandr --current 2>/dev/null | head -1)
    XC=$(pgrep -c Xorg 2>/dev/null || true)

    [ "${XC:-0}" -gt 0 ] && xorg_seen=1
    if [ "$xorg_seen" = 1 ] && [ "${XC:-0}" -eq 0 ]; then
      write_report "xorg-crash" "Xorg process count reached 0"
      xorg_seen=0
    fi

    if [ "$S" = "connected" ]; then
      had_video=1
      disc=0
    elif [ "$had_video" = 1 ] && [ "$S" = "disconnected" ]; then
      disc=$((disc + 1))
      if [ "$disc" -ge 3 ]; then
        write_report "display-lost" "connector became disconnected 3 times in a row ($CONNECTOR)"
        disc=0
      fi
    fi

    if [ -n "$XR" ]; then
      xr_ok=1
    elif [ "$xr_ok" = 1 ]; then
      write_report "xorg-unresponsive" "xrandr stopped responding"
      xr_ok=0
    fi

    printf '[%s] connector=%s xrandr=%s xorg_pids=%s\n' \
      "$(date +%H:%M:%S)" "${S:-?}" "${XR:-NO_RESPONSE}" "${XC:-?}" >> "$SESSION"
    sleep 5
  done
) &
VIDEO_PID=$!
echo "$VIDEO_PID" > "$RUN_DIR/video.pid"

# ---------------------------------------------------------------------------
# Foreground mode or background daemon.
# ---------------------------------------------------------------------------
cleanup() {
  touch "$RUN_DIR/stop" 2>/dev/null || true
  for p in "$DMESG_PID" "$SAMPLE_PID" "$VIDEO_PID"; do
    [ -n "$p" ] && kill "$p" 2>/dev/null || true
  done
  pkill -f 'dmesg --since now --time-format iso -w' 2>/dev/null || true
  pkill -f 'dmesg --time-format iso -w' 2>/dev/null || true
  {
    echo "=== ps4-monitor stopped $(date -Is) ==="
    echo "--- last relevant lines ---"
    grep -iE 'amdgpu|drm|ring|reset|timeout|link|HDMI|connector|temp=|ERROR' "$SESSION" 2>/dev/null | tail -40
  } >> "$SESSION" 2>/dev/null || true
  cp -f /var/log/Xorg.0.log "$LOG_DIR/Xorg.0.log.copy" 2>/dev/null || true
  rm -f "$RUN_DIR/dmesg.pid" "$RUN_DIR/sample.pid" "$RUN_DIR/video.pid" "$RUN_DIR/monitor.pid" "$RUN_DIR/stop"
  echo "ps4-monitor: stopped. Session log: $SESSION"
}

trap cleanup EXIT INT TERM
echo "ps4-monitor: running (pid $$). Session log: $SESSION"
echo "ps4-monitor: press Ctrl-C to stop."
wait
