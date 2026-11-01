#!/bin/bash
# ============================================================================
#  check.sh — verify that the alternative Mesa builds load RADV on this PS4
#
#  USAGE
#    ./check.sh                 # test every available version
#    ./check.sh 26.0.4          # test only one version
#    ./check.sh --list          # list available versions
#    ./check.sh --no-gui        # skip vkcube (useful on a headless session)
#    ./check.sh --help
#
#  Exit status: 0 if every tested version passed, 1 otherwise.
# ============================================================================
set -u
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
STEAM_ROOT="${STEAM_ROOT:-$HOME/.local/share/Steam}"
DISPLAY="${DISPLAY:-}"
XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
# Only assume :0 when an X server is actually listening; on a pure Wayland or
# headless session DISPLAY must stay empty so the GUI test is skipped.
if [ -z "$DISPLAY" ] && [ -S /tmp/.X11-unix/X0 ]; then
  DISPLAY=":0"
fi
export DISPLAY XAUTHORITY

NO_GUI=0
LIST_ONLY=0
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-gui) NO_GUI=1; shift ;;
    --list)   LIST_ONLY=1; shift ;;
    -h|--help)
      awk 'NR==1{next} /^# ============================================================================$/{if (++n==2) exit} {print}' "$0"
      exit 0 ;;
    -*) echo "check: unknown option: $1 (use --help)" >&2; exit 2 ;;
    *)  ARGS+=("$1"); shift ;;
  esac
done

VKINFO=$(command -v vulkaninfo 2>/dev/null || true)
[ -n "$VKINFO" ] || VKINFO="$STEAM_ROOT/ubuntu12_32/steam-runtime/amd64/usr/bin/vulkaninfo"
VKCUBE=$(command -v vkcube 2>/dev/null || true)
[ -n "$VKCUBE" ] || VKCUBE="$STEAM_ROOT/ubuntu12_32/steam-runtime/amd64/usr/bin/vkcube"

# Available versions (explicit override, repository copy, then ~/mesa-versions)
VERS=()
for b in "${VULKAN_MESA_DIR:-}" "$SELF_DIR/mesa-versions" "$HOME/mesa-versions"; do
  [ -n "$b" ] || continue
  [ -d "$b" ] || continue
  for d in "$b"/mesa-*; do
    [ -d "$d" ] || continue
    v="${d##*/mesa-}"
    case " ${VERS[*]-} " in *" $v "*) : ;; *) VERS+=("$v") ;; esac
  done
done
[ ${#ARGS[@]} -gt 0 ] && VERS=("${ARGS[@]}")

if [ "$LIST_ONLY" = 1 ]; then
  if [ ${#VERS[@]} -eq 0 ]; then
    echo "No Mesa versions found in ~/mesa-versions or $SELF_DIR/mesa-versions" >&2
    exit 1
  fi
  printf '%s\n' "${VERS[@]}"
  exit 0
fi

echo "=================================================================="
echo " Alternative Vulkan/RADV check — $(date '+%Y-%m-%d %H:%M')"
echo "=================================================================="

if [ ${#VERS[@]} -eq 0 ]; then
  echo "No Mesa versions found in ~/mesa-versions or $SELF_DIR/mesa-versions"
  echo "Run ./download-mesa.sh or ./install.sh first."
  exit 1
fi
echo "Found versions: ${VERS[*]}"
echo

FAILED=0
TMPLOG=$(mktemp "${TMPDIR:-/tmp}/vkcube-check.XXXXXX.log")
trap 'rm -f "$TMPLOG"' EXIT

failures_before=$(dmesg 2>/dev/null | grep -cE 'ring gfx timeout|Recovery Failed' || true)

for v in "${VERS[@]}"; do
  echo "--- Mesa $v -------------------------------------------------"
  (
    # shellcheck disable=SC1090
    . "$SELF_DIR/vulkan-env.sh" --mesa "$v" --quiet || { echo "  x environment not prepared"; exit 1; }
    if [ -x "$VKINFO" ]; then
      out=$(timeout 40 "$VKINFO" --summary 2>/dev/null)
      rc=$?
      dev=$(printf '%s\n' "$out" | sed -n 's/.*deviceName *= *//p' | head -n1)
      drv=$(printf '%s\n' "$out" | sed -n 's/.*driverInfo *= *//p' | head -n1)
      if [ $rc -eq 0 ] && [ -n "$dev" ]; then
        printf '  vulkaninfo: %s | %s\n' "$dev" "${drv:-?}"
      else
        printf '  vulkaninfo: FAILED (rc=%s)\n' "$rc"
        exit 1
      fi
    else
      echo "  (vulkaninfo not available)"
    fi
    if [ "$NO_GUI" != 1 ] && [ -x "$VKCUBE" ] && [ -n "${DISPLAY:-}" ]; then
      timeout 5 "$VKCUBE" >"$TMPLOG" 2>&1
      rc=$?
      if [ $rc -eq 124 ]; then
        printf '  vkcube: OK (rendered for 5 s)\n'
      else
        printf '  vkcube: FAILED (rc=%s)\n' "$rc"
        tail -3 "$TMPLOG" | sed 's/^/    /'
        exit 1
      fi
    elif [ "$NO_GUI" != 1 ]; then
      echo "  (vkcube/DISPLAY not available; skipping GUI test)"
    fi
    exit 0
  ) || FAILED=$((FAILED + 1))
done

failures_after=$(dmesg 2>/dev/null | grep -cE 'ring gfx timeout|Recovery Failed' || true)
echo
echo "=================================================================="
echo "GPU failures during the check: $((failures_after - failures_before))"
TEMP=$(cat /sys/devices/platform/ps4-fan/hwmon/hwmon0/temp1_input 2>/dev/null)
[ -n "$TEMP" ] && echo "Current temperature: $((TEMP / 1000)) °C"
echo "System Mesa: $(timeout 6 glxinfo -B 2>/dev/null | sed -n 's/.*Device: //p' | head -n1)"
echo "=================================================================="

if [ "$FAILED" -gt 0 ]; then
  echo "RESULT: $FAILED version(s) failed."
  exit 1
fi
echo "RESULT: all tested versions passed."
exit 0
